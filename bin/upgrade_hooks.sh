#!/bin/bash
#
# Copyright (c) 2013, Joyent, Inc., All rights reserved.
#
# These upgrade hooks are called from headnode.sh during the first boot
# after we initiated the upgrade in order to complete the upgrade steps.
#
# Usage:
#       ${SDC_UPGRADE_DIR}/upgrade_hooks.sh HOOK [ZONENAME]
#
# The "pre" and "post" hooks are called before headnode does any setup
# and after the setup is complete.
#
# The role-specific hooks are called after each zone role has been setup.
#

unset LD_LIBRARY_PATH
PATH=/usr/bin:/usr/sbin:/opt/smartdc/bin:/smartdc/bin
export PATH

BASH_XTRACEFD=4
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

. /lib/sdc/config.sh



#---- globals

# time to wait for each zone to setup (in seconds)
ZONE_SETUP_TIMEOUT=180

SDC_UPGRADE_DIR=/var/upgrade_headnode

# We have to install the extra zones in dependency order
EXTRA_ZONES="sdcsso cloudapi"



#---- setup state support
# "/var/lib/setup.json" support is duplicated in headnode.sh and
# upgrade_hooks.sh. These must be kept in sync.
# TODO: share these somewhere

SETUP_FILE=/var/lib/setup.json

function update_setup_state
{
    STATE=$1

    chmod 600 $SETUP_FILE
    cat "$SETUP_FILE" | json -e \
        "this.current_state = '$STATE';
         this.last_updated = new Date().toISOString();
         this.seen_states.push('$STATE');" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
}

function mark_as_setup
{
    chmod 600 $SETUP_FILE
    # Update the setup state file with the new value
    cat "$SETUP_FILE" | json -e "this.complete = true;
         this.current_state = 'setup_complete';
         this.seen_states.push('setup_complete');
         this.last_updated = new Date().toISOString();" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
    sysinfo -u
}


#---- support functions

saw_err()
{
    echo "    $1" >> ${SDC_UPGRADE_DIR}/error_finalize.txt
}

shutdown_zone()
{
	zlogin $1 /usr/sbin/shutdown -y -g 0 -i 5 1>&4 2>&1

	# Check for zone being down and halt it forcefully if needed
	local cnt=0
	while [[ $cnt -lt 18 ]]; do
		sleep 5
		local zstate=`zoneadm -z $1 list -p | cut -f3 -d:`
		[[ "$zstate" == "installed" ]] && break
		cnt=$(($cnt + 1))
	done

	# After 90 seconds, shutdown harder
	[[ $cnt == 18 ]] && zoneadm -z $1 halt
}

print_log()
{
    echo "$@" | tee -a /tmp/upgrade_progress >/dev/console
}

create_extra_zones()
{
    declare -A existing_zones=()

    for i in `sdc-role list | nawk '{if ($6 != "ROLE") print $6}'`
    do
        existing_zones[$i]=1
    done

    local new_uuid=
    local loops=
    local zonepath=
    local ext_role=
    local ext_ip=
    local ext_ip_arg=
    local res=
    local hn_uuid=$(sysinfo | json UUID)

    for i in $EXTRA_ZONES
    do
        [[ ${existing_zones[$i]} == 1 ]] && continue

        print_log "creating zone $i..."

        # 6.5.x billapi role is now usageapi role, lookup billapi external IP
        ext_role=$i
        [ "$i" == "usageapi" ] && ext_role="billapi"

        ext_ip=`nawk -v role=$ext_role '{
            if ($1 == role) print $2
        }' ${SDC_UPGRADE_DIR}/ext_addrs.txt`
        ext_ip_arg=""
        [ -n "$ext_ip" ] && ext_ip_arg="-o external_ip=$ext_ip"

        sdc-role create $ext_ip_arg $hn_uuid $i 1>/tmp/role.out.$$ 2>&1
        res=$?
        cat /tmp/role.out.$$ 1>&4
        if [ $res != 0 ]; then
            saw_err "Error creating $i zone"
            mv /tmp/payload.* ${SDC_UPGRADE_DIR}
            mv /tmp/provision.* ${SDC_UPGRADE_DIR}

            # Capture the job info into the log
            local job=`nawk '/Job is/{print $NF}' /tmp/role.out.$$`
            [ -n "$job" ] && \
                curl -i -s \
                    http://${CONFIG_vmapi_admin_ips}/${job} | json 1>&4 2>&1

            rm -f /tmp/role.out.$$
            continue
        fi
        rm -f /tmp/role.out.$$

        new_uuid=`sdc-role list | nawk -v role=$i '{if ($6 == role) print $3}'`
        if [[ -z "$new_uuid" ]]; then
            saw_err "Error creating $i zone: not found"
            continue
        fi

        zonepath=$(vmadm get ${new_uuid} | json zonepath)
        if [[ -z ${zonepath} ]]; then
            saw_err "Error creating $i zone: no zonepath"
            continue
        fi

        loops=0
        while [[ ! -f ${zonepath}/root/var/svc/setup_complete \
            && ! -f ${zonepath}/root/var/svc/setup_failed \
            && $loops -lt ${ZONE_SETUP_TIMEOUT} ]]
        do
            sleep 1
            loops=$((${loops} + 1))
        done

        if [[ ${loops} -lt ${ZONE_SETUP_TIMEOUT} && \
            -f ${zonepath}/root/var/svc/setup_complete ]]; then

            # Got here and complete, now just wait for services.
            while [[ -n $(svcs -xz ${new_uuid}) && \
                $loops -lt ${ZONE_SETUP_TIMEOUT} ]]
            do
                sleep 1
                loops=$((${loops} + 1))
            done
        fi

        if [[ ${loops} -ge ${ZONE_SETUP_TIMEOUT} ]]; then
            saw_err "Error creating $i zone: setup timed out"
        elif [[ -f ${zonepath}/root/var/svc/setup_failed ]]; then
            saw_err "Error creating $i zone: setup failed"
        elif [[ -n $(svcs -xz ${new_uuid}) ]]; then
            saw_err "Error creating $i zone: svcs error"
        else
            # Zone is setup ok, run the post-setup hook
            print_log "upgrading zone $i..."
            ${SDC_UPGRADE_DIR}/upgrade_hooks.sh $i ${new_uuid} \
              4>${SDC_UPGRADE_DIR}/finish_${i}.log
        fi
    done
}

convert_portal_zone()
{
    zoneadm -z portal list -p >/dev/null 2>&1
    [ $? -ne 0 ] && return

    local uuid=`zonecfg -z portal info uuid | cut -d' ' -f2`

    if [ -z "$uuid" ]; then
        saw_err "Error: portal zone is missing a UUID"
        return
    fi

    zoneadm -z portal move /zones/$uuid
    zonecfg -z portal set zonename=$uuid
    vmadm update $uuid alias=portal0
    zoneadm -z $uuid boot
}

pre_tasks()
{
    # If pre-existing portal zone, shut it down for now.
    zoneadm -z portal halt >/dev/null 2>&1

    # The following img setup code duplicates the imgadm setup behavior from
    # joysetup.sh. That work is done on initial install of the HN, but
    # joysetup.sh is not run when we upgrade a installed HN.

    if [[ ! -f /var/db/imgadm/sources.list ]]; then
        # For now we initialize with the global one since we don't have a local
        # imgapi yet.
        mkdir -p /var/db/imgadm
        echo "https://datasets.joyent.com/datasets/" \
            > /var/db/imgadm/sources.list
        imgadm update
    fi

    if [[ ! -f /var/imgadm/imgadm.conf ]]; then
        # pickup config
        load_sdc_config

        mkdir -p /var/imgadm
        imgapi_url=http://$(echo $CONFIG_imgapi_admin_ips | cut -d, -f1)
        echo '{}' | /usr/bin/json -e "this.sources=[{\"url\": \"$imgapi_url\", \"type\": \"imgapi\"}]" \
            > /var/imgadm/imgadm.conf
    fi

    # Now create the install progress status file that is required by
    # headnode.sh. This is normally done in joysetup.sh, but again, we don't
    # run that on upgrade.
    if [[ -e /var/lib/setup.json ]]; then
        chmod +w /var/lib/setup.json
    fi
    echo "{" \
        "\"node_type\": \"headnode\"," \
        "\"start_time\": \"$(date "+%Y-%m-%dT%H:%M:%SZ")\"," \
        "\"current_state\": \"imgadm_setup\"," \
        "\"seen_states\": [" \
        "\"zpool_created\"," \
        "\"filesystems_setup\"," \
        "\"imgadm_setup\"" \
        "]," \
        "\"complete\": false," \
        "\"last_updated\": \"$(date "+%Y-%m-%dT%H:%M:%SZ")\"" \
        "}" >/var/lib/setup.json
    chmod 400 /var/lib/setup.json

    print_log \
        "If an unrecoverable error occurs, use sdc-rollback to return to 6.5"
}

post_tasks()
{
    # Need to wait for all svcs to be up before we can create additional zones
    # Give headnode.sh a second to emit all of its messages.
    sleep 1
    print_log "Upgrade: waiting for all svcs to be ready..."
    loops=0
    while [[ -n $(svcs -x) && $loops -lt ${ZONE_SETUP_TIMEOUT} ]]
    do
        sleep 1
        loops=$((${loops} + 1))
    done

    if [[ ${loops} -ge ${ZONE_SETUP_TIMEOUT} ]]; then
        saw_err "Error global zone: svcs timed out"
        print_log "Upgrade: ERROR global zone: svcs check timed out"
    else
        print_log "Upgrade: all svcs are ready, continuing..."
    fi

    # load config to pick up latest settings
    load_sdc_config

    # We have to wait until moray, wf, cnapi, etc. are responding
    local loops=0
    while [ $loops -lt 20 ]; do
        up=`sdc-role list 2>/dev/null | grep ufds`
        [ -n "$up" ] && break
        print_log "Waiting for the core zones to be ready..."
        sleep 30
        loops=$((${loops} + 1))
    done

    [ $loops -eq 20 ] && \
        print_log "Core zones are still not ready, continuing but errors" \
	"are likely"

    # XXX
    sleep 30

    print_log "configuring fwapi..."
    fwapi_tasks

    print_log "upgrading napi data..."
    napi_tasks `cat ${SDC_UPGRADE_DIR}/napi_zonename.txt`

    create_extra_zones

    convert_portal_zone

    dname="/var/upgrade.$(date -u "+%Y%m%dT%H%M%S")"

    local ufds_uuid=`vmadm lookup -1 tags.smartdc_role=ufds`
    if [ $? -ne 0 ]; then
        saw_err "Error, missing uuid for ufds zone"
    else
        # Add external net
        cat <<-EXT_DONE >${SDC_UPGRADE_DIR}/ufds_extnic.json
	{
	    "add_nics": [
	        {
	            "interface": "net1",
	            "nic_tag": "external",
	            "ip": "$CONFIG_ufds_external_ips",
	            "netmask": "$CONFIG_external_netmask",
	            "gateway": "$CONFIG_external_gateway"
	        }
	    ]
	}
	EXT_DONE

        vmadm update -f ${SDC_UPGRADE_DIR}/ufds_extnic.json $ufds_uuid
        vmadm update $ufds_uuid firewall_enabled=true
        reboot_ufds $ufds_uuid
    fi

    # XXX Install old platforms used by CNs

    print_log ""
    print_log "The upgrade is finished"
    print_log "Note the following items:"

    mv ${SDC_UPGRADE_DIR} $dname
    # If no error setting up cloudapi, print read-only msg
    local cloudapi_failed=0
    if [ -f $dname/error_finalize.txt ]; then
        egrep -s cloudapi $dname/error_finalize.txt
        [ $? == 0 ] && cloudapi_failed=1
    fi
    if [ $cloudapi_failed == 0 ]; then
        print_log "- CloudAPI is currently in read-only mode"
        print_log "  When ready, enable read-write using sdc-post-upgrade -w"
    fi
    [ -s $dname/capi_conversion_issues.txt ] && \
        echo "- Review CAPI issues in capi_conversion_issues.txt"

    if [[ $CONFIG_ufds_is_local == "true" ]]; then
        print_log "- If remote sites were accessing CAPI, you must"
        print_log "  update the UFDS firewall rule $FW_UUID"
        print_log "  $FW_RULE"
    fi

    print_log "- The upgrade logs are in $dname"
    update_setup_state "upgrade_complete"

    if [ -f $dname/error_finalize.txt ]; then
        print_log "- ERRORS during upgrade:"
        cat $dname/error_finalize.txt | tee -a /tmp/upgrade_progress \
            >/dev/console
        print_log "You must resolve these errors before the headnode is usable"
        exit 1
    else
        mark_as_setup
    fi
    print_log "DONE"
}

reboot_ufds()
{
    vmadm reboot $1
    sleep 10

    # Wait for the zone to fully come back up
    loops=0
    # Got here and complete, now just wait for services.
    while [[ -n $(svcs -xz $1) && $loops -lt ${ZONE_SETUP_TIMEOUT} ]]
    do
        sleep 1
        loops=$((${loops} + 1))
    done

    [[ ${loops} -ge ${ZONE_SETUP_TIMEOUT} ]] && \
        saw_err "Error restarting ufds zone: svcs did not completely restart"
}

# arg1 is zonename
ufds_tasks()
{
    # load config to pick up settings for newly created ufds zone
    load_sdc_config

    if [[ $CONFIG_ufds_is_local != "true" ]]; then
	local zpath=/zones/$1/root/opt/smartdc/ufds

        sed -e "s/REMOTE_UFDS_IP/$CONFIG_ufds_remote_ip/" \
            -e "s/REMOTE_QUERY/\/ou=users, o=smartdc??sub?/" \
            -e "s/REMOTE_ROOT_DN/$CONFIG_ufds_ldap_root_dn/" \
            -e "s/REMOTE_ROOT_PW/$CONFIG_ufds_ldap_root_pw/" \
            -I .bak $zpath/etc/replicator.json.in

	# Update the main json file. configure will do this again on reboot
	cp $zpath/etc/replicator.json.in $zpath/etc/replicator.json

	# import and restart the replicator service
	cp $zpath/smf/manifests/ufds-replicator.xml.in \
	    $zpath/smf/manifests/ufds-replicator.xml
	zlogin $1 svccfg import \
	    /opt/smartdc/ufds/smf/manifests/ufds-replicator.xml
	zlogin $1 svcadm refresh ufds-replicator

        return
    fi

    ufds_ip=`vmadm list -o nics.0.ip -H uuid=$1`
    client_url="ldaps://${ufds_ip}"

    # Delete the newly created admin user since we'll have a dup when we
    # reload from the dump
    zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapdelete \
        -H ${client_url} \
        -D ${CONFIG_ufds_ldap_root_dn} \
        -w ${CONFIG_ufds_ldap_root_pw} \
        "uuid=${CONFIG_ufds_admin_uuid},ou=users,o=smartdc" 1>&4 2>&1
    [ $? != 0 ] && \
        saw_err "Error loading CAPI data into UFDS - deleting admin user"

    cp ${SDC_UPGRADE_DIR}/capi_dump/ufds.ldif /zones/$1/root
    zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
        -H ${client_url} \
        -D ${CONFIG_ufds_ldap_root_dn} \
        -w ${CONFIG_ufds_ldap_root_pw} \
        -M \
        -f /ufds.ldif >${SDC_UPGRADE_DIR}/ufds_capi_load.txt 2>&4
    local res=$?
    [[ $res != 0 ]] && saw_err "Error loading CAPI data into UFDS"

    cp ${SDC_UPGRADE_DIR}/mapi_dump/mapi-ufds.ldif /zones/$1/root
    zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
        -H ${client_url} \
        -D ${CONFIG_ufds_ldap_root_dn} \
        -w ${CONFIG_ufds_ldap_root_pw} \
        -M \
        -f /mapi-ufds.ldif >${SDC_UPGRADE_DIR}/ufds_mapi_load.txt 2>&4
    res=$?
    [[ $res != 0 ]] && saw_err "Error loading MAPI data into UFDS"
}

# arg1 is zonename
imgapi_tasks()
{
    # Load all the images in SDC_UPGRADE_DIR/mapi_dump/images.json.
    local images=$(cat $SDC_UPGRADE_DIR/mapi_dump/images.json)
    local numImages=$(echo "$images" | json length)
    local i=0
    while [ $i -lt $numImages ]; do
        local imageFile=$(echo "$images" | json $i._local_path)
        local image=$(echo "$images" | json -e 'this._local_path = undefined' $i)
        local uuid=$(echo "$image" | json uuid)
        local status=$(/opt/smartdc/bin/sdc-imgapi /images/$uuid \
            | head -1 | awk '{print $2}')
        if [[ "$status" == "404" ]]; then
            echo "Importing image $uuid ($file) into IMGAPI."
            if [[ -f $imageFile ]]; then
                echo "$image" | /opt/smartdc/bin/sdc-imgadm import -f $imageFile
                local res=$?
                if [[ $res == 0 ]]; then
                    rm $imageFile
                else
                    saw_err "Error importing image $uuid $(file) into IMGAPI"
                fi
            else
                saw_err "Image $uuid file $imageFile not found."
            fi
        elif [[ "$status" == "200" ]]; then
            echo "Skipping import of image $uuid: already in IMGAPI."
        else
            saw_err "Error checking if image $uuid is in IMGAPI: HTTP $status"
        fi
        i=$(($i + 1))
    done
}

# arg1 is zonename
napi_tasks()
{
    cp ${SDC_UPGRADE_DIR}/mapi_dump/napi*.moray /zones/$1/root/root

    zlogin $1 /opt/smartdc/napi/sbin/import-data /root 1>&4 2>&1
    [ $? != 0 ] && \
        saw_err "Error loading NAPI data into moray"

    # reserve the IP addrs we stole out of the dhcp range for the new zones
    local admin_uuid=`zlogin $1 /opt/smartdc/napi/bin/napictl network-list | \
        json -a name uuid | nawk '{if ($1 == "admin") print $2}'`
    if [ -z "$admin_uuid" ]; then
        saw_err "Error, missing uuid for admin network"
        return
    fi

    for a in `cat ${SDC_UPGRADE_DIR}/allocated_addrs.txt`
    do
        local z_uuid=`vmadm list -o uuid nics.0.ip=$a -H`
        [ -z "$z_uuid" ] && saw_err "Error, missing zone for $a"

        zlogin $1 /opt/smartdc/napi/bin/napictl ip-update $admin_uuid $a \
            owner_uuid="00000000-0000-0000-0000-000000000000" \
            belongs_to_uuid="$z_uuid" belongs_to_type=zone reserved=true \
            1>&4 2>&1
        [ $? != 0 ] && saw_err "Error reserving IP $a for zone $z_uuid"
    done
}

netmask_to_cidr()
{
    cidr=`echo "$1" | nawk '
        BEGIN {
            bits = 8
            for (i = 255; i >=0; i -= 2^i++)
                cidr[i] = bits--
        }
        {
            split($1, a, "[.]")
            for (i = 1; i <= 4; i++)
                tot += cidr[a[i]]

            print tot
        }'`
}

fwapi_tasks()
{
    local ufds_uuid=`vmadm lookup -1 tags.smartdc_role=ufds`
    if [ $? -ne 0 ]; then
        saw_err "Error, missing uuid for ufds zone"
        return
    fi

    local fwapi_uuid=`vmadm lookup -1 tags.smartdc_role=fwapi`
    if [ $? -ne 0 ]; then
        saw_err "Error, missing uuid for fwapi zone"
        return
    fi

    local portal_ip=`nawk '{if ($1 == "portal") print $2}' \
        ${SDC_UPGRADE_DIR}/ext_addrs.txt`

    netmask_to_cidr $CONFIG_admin_netmask
    cat <<-FW_DONE >/zones/$fwapi_uuid/root/root/fwrules.json
	{ "enabled": true,
	  "owner_uuid": "00000000-0000-0000-0000-000000000000",
	  "rule": "FROM (subnet ${CONFIG_admin_network}/$cidr OR ip $portal_ip) TO machine $ufds_uuid ALLOW tcp (port 8080 AND port 636)"
	}
	FW_DONE
    zlogin $fwapi_uuid /opt/smartdc/fwapi/bin/fwapi add -f /root/fwrules.json \
        >${SDC_UPGRADE_DIR}/fw_setup.txt 2>&1
    [ $? -ne 0 ] && saw_err "Error, setting up firewall rules for ufds zone"
    FW_UUID=`json uuid <${SDC_UPGRADE_DIR}/fw_setup.txt 2>/dev/null`
    FW_RULE=`json rule <${SDC_UPGRADE_DIR}/fw_setup.txt 2>/dev/null`
}

# arg1 is zonename
cloudapi_tasks()
{
    # We're going to replace the config files, so halt the zone
    shutdown_zone $1

    # Parts of the 6.5.x backup are compatible with the 7.0 cloudapi
    # configuration, but not all, so restore what we can and convert the rest.

    local bdir=${SDC_UPGRADE_DIR}/bu.tmp/cloudapi

    # The plugin and ssl config is compatible
    mkdir -p /zones/$1/root/opt/smartdc/cloudapi/plugins
    if [[ -d "$bdir/plugins" ]]; then
        for i in `ls $bdir/plugins`
        do
            if [ -d $bdir/plugins/$i ]; then
                cp -pr $bdir/plugins/$i \
                    /zones/$1/root/opt/smartdc/cloudapi/plugins
            elif [ ! -f /zones/$1/root/opt/smartdc/cloudapi/plugins/$i ]; then
                cp -p $bdir/plugins/$i \
                    /zones/$1/root/opt/smartdc/cloudapi/plugins
            fi
        done
    fi

    if [[ -d "$bdir/ssl" ]]; then
        mkdir -p /zones/$1/root/opt/smartdc/cloudapi/ssl
        cp -p $bdir/ssl/* /zones/$1/root/opt/smartdc/cloudapi/ssl
    fi

    # The config file needs conversion
    local ocfg=$bdir/config.json
    local cfgfile=/zones/$1/root/opt/smartdc/cloudapi/etc/cloudapi.cfg

    /usr/node/bin/node -e '
        var fs = require("fs");
        var path = require("path");
        var oldPath = process.argv[1];
        var cfgPath = process.argv[2];

        var old = JSON.parse(fs.readFileSync(oldPath));
        var cfg = JSON.parse(fs.readFileSync(cfgPath));

        cfg.read_only = true;
        cfg.datacenters = old.datacenters;
        cfg.userThrottles = old.userThrottles;

        // Get old plugins.
        var oldExtraPlugins = [];
        var oldCapiLimits = null;
        var oldMachineEmail = null;

        if (old.preProvisionHook instanceof Array) {
            old.preProvisionHook.forEach(function (oldPlugin) {
                if (oldPlugin.plugin === "./plugins/capi_limits") {
                    oldCapiLimits = oldPlugin;
                } else {
                    oldExtraPlugins.push(oldPlugin);
                }
            });
        } else {
            oldCapiLimits = old.preProvisionHook;
        }

        if (old.postProvisionHook instanceof Array) {
            old.postProvisionHook.forEach(function (oldPlugin) {
                if (oldPlugin.plugin === "./plugins/machine_email") {
                    oldMachineEmail = oldPlugin;
                } else {
                    oldExtraPlugins.push(oldPlugin);
                }
            });
        } else {
            oldMachineEmail = old.postProvisionHook;
        }

        // update existing plugins
        cfg.plugins.forEach(function (p) {
            if (p.name === "capi_limits") {
                if (oldCapiLimits != null) {
                    p.enabled = oldCapiLimits.enabled;
                    p.config = oldCapiLimits.config;
                }
            } else if (p.name === "machine_email") {
                if (oldMachineEmail != null) {
                    p.enabled = oldMachineEmail.enabled;
                    p.config.from = oldMachineEmail.config.from;
                    p.config.subject = oldMachineEmail.config.subject;
                    p.config.body = oldMachineEmail.config.body;
                }
            }
        });

        // add extra plugins
        oldExtraPlugins.forEach(function (p) {
            p.name = path.basename(p.plugin);
            delete p.plugin;
            cfg.plugins.push(p);
        });

        console.log(JSON.stringify(cfg, null, 2));
    ' $ocfg $cfgfile >$cfgfile.new

    cp $cfgfile $cfgfile.bak
    cp $cfgfile.new $cfgfile
    rm -f $cfgfile.new

    # Boot the zone with the new config data
    zoneadm -z $1 boot
}



#---- mainline

case "$1" in
"pre") pre_tasks;;

"post") print_log "Finishing the upgrade in the background"
        ${SDC_UPGRADE_DIR}/upgrade_hooks.sh "post_bg" \
            4>${SDC_UPGRADE_DIR}/finish_post.log &
        ;;

"post_bg") post_tasks;;

"cloudapi") cloudapi_tasks $2;;

"ufds") ufds_tasks $2;;

"imgapi") imgapi_tasks $2;;

"napi") echo "$2" >${SDC_UPGRADE_DIR}/napi_zonename.txt;;
esac

exit 0
