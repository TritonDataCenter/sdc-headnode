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

# Install cloudapi first so sdcsso doesn't steal cloudapi's external IP addr.
EXTRA_ZONES="cloudapi sdcsso"

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
    local ext_ip=
    local ext_ip_arg=
    local res=
    local hn_uuid=$(sysinfo | json UUID)

    for i in $EXTRA_ZONES
    do
        [[ ${existing_zones[$i]} == 1 ]] && continue

        print_log "creating zone $i..."

        ext_ip=`nawk -v role=$i '{if ($1 == role) print $2 }' \
            ${SDC_UPGRADE_DIR}/ext_addrs.txt`

        local service_uuid=$(sdc-sapi /services?name=$i | json -H 0.uuid)
        local payload="{
            \"service_uuid\": \"$service_uuid\",
            \"params\": {
                \"alias\": \"${i}0\",
                \"networks\": [
                    {
                        \"uuid\": \"$(sdc-napi /networks | json -H -c 'this.nic_tag=="admin"' 0.uuid)\"
                    }
                ]
            }
        }"
        if [[ -n "$ext_ip" ]]; then
            payload=$(echo "$payload" | json -e "this.params.networks.push({
                \"uuid\": \"$(sdc-napi /networks | json -H -c 'this.nic_tag=="external"' 0.uuid)\",
                \"ip\": \"$ext_ip\",
                \"primary\": true
            })")
        fi
        echo "$payload" | sapiadm provision

        res=$?
        if [ $res != 0 ]; then
            saw_err "Error creating $i zone"
            continue
        fi

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
    # add missing rctls
    local pmem=`zonecfg -z $uuid info capped-memory | \
        nawk '{if ($1 == "[physical:") print substr($2, 1, length($2) - 2)}'`
    if [ -z "$pmem" ]; then
        pmem="8g"
        echo "set zfs-io-priority=20; add capped-memory; set swap=$pmem; " \
            "set locked=$pmem; set physical=$pmem; end" | zonecfg -z $uuid
    else
        if [ $pmem -gt 8 ]; then
            pmem="8g"
        else
            pmem="${pmem}g"
        fi
        echo "set zfs-io-priority=20; select capped-memory; set swap=$pmem; " \
            "set locked=$pmem; set physical=$pmem; end" | zonecfg -z $uuid
    fi
    vmadm update $uuid alias=portal0
    echo '{"set_tags": {"smartdc_role": "portal"}}' | vmadm update $uuid

    local mac=`vmadm get $uuid | json nics | json -a mac`
    if [ -z "$mac" ]; then
        saw_err "Error: portal zone is missing the mac address"
        return
    fi

    # set primary on external net
    cat <<-EXT_DONE >${SDC_UPGRADE_DIR}/portal_extnic.json
	{
	    "update_nics": [
	        {
	            "mac": "$mac",
	            "primary": true
	        }
	    ]
	}
	EXT_DONE

    vmadm update -f ${SDC_UPGRADE_DIR}/portal_extnic.json $uuid


    zoneadm -z $uuid boot
}

pre_tasks()
{
    echo "$(date -u "+%Y%m%dT%H%M%S") 7.0 start" >>$SDC_UPGRADE_DIR/upgrade_time

    # If pre-existing portal zone, shut it down for now.
    zoneadm -z portal halt >/dev/null 2>&1

    # The following img setup code duplicates the imgadm setup behavior from
    # joysetup.sh. That work is done on initial install of the HN, but
    # joysetup.sh is not run when we upgrade a installed HN.

    # imgadm setup to use the IMGAPI in this DC.
    if [[ ! -f /var/imgadm/imgadm.conf ]]; then
        mkdir -p /var/imgadm
        echo '{}' > /var/imgadm/imgadm.conf
    fi
    if [[ -z "$(json -f /var/imgadm/imgadm.conf sources)" ]]; then
        # pickup config
        load_sdc_config

        imgadm sources -f -a http://$CONFIG_imgapi_domain
        imgadm sources -f -d https://images.joyent.com  # remove the default
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
        "\"filesystems_setup\"" \
        "]," \
        "\"complete\": false," \
        "\"last_updated\": \"$(date "+%Y-%m-%dT%H:%M:%SZ")\"" \
        "}" >/var/lib/setup.json
    chmod 400 /var/lib/setup.json

    update_setup_state "imgadm_setup"

    print_log \
        "If an unrecoverable error occurs, use sdc-rollback to return to 6.5"
}

# arg1 role
add_ext_net()
{
    local role=$1

    role_uuid=`vmadm lookup -1 tags.smartdc_role=${role}`
    if [ $? -ne 0 ]; then
        saw_err "Error, missing uuid for ${role} zone"
        return
    fi

    local ext_uuid=`sdc-login napi /opt/smartdc/napi/bin/napictl \
        network-list | \
        json -a name uuid | nawk '{if ($1 == "external") print $2}'`
    if [ -z "$ext_uuid" ]; then
        saw_err "Error, missing uuid for external network"
        return
    fi

    local key="${role}_external_ips"
    local ext_ip=$(eval "echo \${CONFIG_${key}}")
    if [ -z "$ext_ip" ]; then
        ext_ip=`sdc-login napi /opt/smartdc/napi/bin/napictl nic-provision \
            ${ext_uuid} \
            owner_uuid=${CONFIG_ufds_admin_uuid} \
            belongs_to_uuid=${role_uuid} \
            belongs_to_type=zone | \
            json ip`
        if [ -z "$ext_ip" ]; then
            saw_err "Error, unable to allocate external IP for $role"
            return
        fi
    fi

    key="${role}_external_vlan"
    local ext_vlan=$(eval "echo \${CONFIG_${key}}")
    [ -z "$ext_vlan" ] && ext_vlan=$CONFIG_external_vlan_id
    [ -z "$ext_vlan" ] && ext_vlan=0

    # Add external net
    cat <<-EXT_DONE >${SDC_UPGRADE_DIR}/${role}_extnic.json
	{
	    "add_nics": [
	        {
	            "interface": "net1",
	            "nic_tag": "external",
	            "ip": "${ext_ip}",
	            "vlan_id": ${ext_vlan},
	            "primary": true,
	            "netmask": "$CONFIG_external_netmask",
	            "gateway": "$CONFIG_external_gateway"
	        }
	    ]
	}
	EXT_DONE

    vmadm update -f ${SDC_UPGRADE_DIR}/${role}_extnic.json $role_uuid

    # Reserve the external IP for the zone
    sdc-login napi /opt/smartdc/napi/bin/napictl ip-update $ext_uuid $ext_ip \
	owner_uuid="${CONFIG_ufds_admin_uuid}" \
	belongs_to_uuid=\"$role_uuid\" belongs_to_type=zone \
	reserved=true  1>&4 2>&1
	[ $? != 0 ] && saw_err "Error reserving IP $a for zone $z_uuid"
}

resv_cns()
{
    print_log "reserving compute nodes..."
    dump=$1

    local i=""
    for i in `nawk -F\t '{
        if (NF != 30) next 
	    if ($2 == "headnode") next
	    if ($7 == "f") next
	    print $17
        }'  ${SDC_UPGRADE_DIR}/mapi_dump/servers.dump`
    do
        sdc-cnapi /servers/$i -X POST -d '{ "reserved": true }' \
            >> ${SDC_UPGRADE_DIR}/res_cn.out 2>&1
    done
}

add_notes()
{
    print_log "adding notes..."

    local moray_uuid=`vmadm lookup -1 tags.smartdc_role=moray`

    local old_ifs=$IFS
    IFS=$'\n'
    local i=""
    for i in `cat ${SDC_UPGRADE_DIR}/notes.out`
    do
	d=`echo "$i" | nawk '{sub("\047", "\047\\\\\047\047"); print $0}'`

	cat <<- PROG >/zones/$moray_uuid/root/root/addnote
	export PATH=/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin:/opt/smartdc/moray/build/node/bin:/opt/smartdc/moray/node_modules/.bin:/opt/smartdc/moray/node_modules/moray/bin

	putobject -d '$d' sdcnotes $(uuid)
	PROG
        zlogin $moray_uuid "bash /root/addnote"
    done
    IFS=$old_ifs

    rm -f /zones/$moray_uuid/root/root/addnote
}

get_replicator_status()
{
    local log=/var/svc/log/smartdc-application-ufds-replicator:default.log

    changelog_num=`nawk '{
            pos = index($0, "Updated changenumber to")
            if (pos == 0)
                next
            s = substr($0, pos + 24)
            pos = index(s, "\"") - 1
            n = substr(s, 1, pos)
        }
        END {print n}' /zones/$1/root/$log`

    egrep -s "No new changelog entries" /zones/$1/root/$log
    replicator_done=$?
}

post_tasks()
{
    echo "$(date -u "+%Y%m%dT%H%M%S") post start" \
        >>$SDC_UPGRADE_DIR/upgrade_time

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

    mkdir -p /usbkey/extra/usbkey
    (cd /usbkey; tar cbfE 512 /usbkey/extra/usbkey/upgrade.tar \
	boot dos firmware)
    gzip /usbkey/extra/usbkey/upgrade.tar
    mv /usbkey/extra/usbkey/upgrade.tar.gz /usbkey/extra/usbkey/cnkey.tgz

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

    # Can still see timeouts in coal when things are spinning up
    [[ "$CONFIG_coal" == "true" ]] && sleep 120

    print_log "upgrading imgapi..."
    imgapi_tasks

    print_log "configuring fwapi..."
    fwapi_tasks

    print_log "upgrading napi data..."
    napi_tasks `cat ${SDC_UPGRADE_DIR}/napi_zonename.txt`

    print_log "upgrading vmapi data"
    vmapi_tasks `cat ${SDC_UPGRADE_DIR}/vmapi_zonename.txt`

    print_log "Adding additional zone external nics"
    add_ext_net ufds
    vmadm update $role_uuid firewall_enabled=true
    reboot_zone $role_uuid

    add_ext_net adminui
    reboot_zone $role_uuid

    add_ext_net amon
    vmadm update $role_uuid firewall_enabled=true
    reboot_zone $role_uuid

    add_ext_net imgapi
    vmadm update $role_uuid firewall_enabled=true
    reboot_zone $role_uuid

    resv_cns
    add_notes

    local ufds_uuid=`vmadm lookup -1 tags.smartdc_role=ufds`
    local pct=0
    local totcl=0

    if [[ $CONFIG_ufds_is_master != "true" ]]; then
        # determine approx. how many changelog entries we need to replicate
        echo "PATH=/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin:/opt/smartdc/ufds/build/node/bin:/opt/smartdc/ufds/node_modules/.bin" \
            >/zones/$ufds_uuid/root/tmp/cnt
        echo "LDAPTLS_REQCERT=allow ldapsearch -x -LLL" \
            "-H ldaps://$CONFIG_ufds_remote_ip -D $CONFIG_ufds_ldap_root_dn" \
            "-w $CONFIG_ufds_ldap_root_pw -b cn=changelogcount" \
            "'(&(objetclass=*))'" >>/zones/$ufds_uuid/root/tmp/cnt

        totcl=`zlogin $ufds_uuid bash /tmp/cnt | \
            nawk '{if ($1 == "count:") print $2}'`

        print_log "There are $totcl changelog entries to be replicated"

        [[ -z "$totcl" || $totcl == 0 ]] && totcl=1

        # We have to wait until the admin user has replicated over
        loops=0
        local nadmin=0
        while [ $loops -lt 90 ]; do
            nadmin=`sdc-ldap search uuid=$CONFIG_ufds_admin_uuid dn \
                2>/dev/null | wc -l`
            [ $nadmin -ne 0 ] && break
            get_replicator_status $ufds_uuid
            pct=$((($changelog_num * 100) / $totcl))
            print_log "Waiting for the admin user to be replicated ($pct%)..."
            sleep 60
            loops=$((${loops} + 1))
        done

        [ $loops -eq 90 ] && \
            print_log "admin user is still not replicated, continuing but" \
                "errors are likely"
    fi

    create_extra_zones

    print_log "Updating the portal zone"
    convert_portal_zone

    # fix ubuntu image size if we have the image
    local uimgid=56108678-1183-11e1-83c3-ff3185a5b47
    sdc-imgadm get $uimgid >/dev/null 2>&1 && \
       sdc-imgadm update $uimgid image_size=5120 || true

    if [[ $CONFIG_ufds_is_master != "true" ]]; then
        # Get an updated total number of changelogs
        totcl=`zlogin $ufds_uuid bash /tmp/cnt | \
            nawk '{if ($1 == "count:") print $2}'`
        [[ -z "$totcl" || $totcl == 0 ]] && totcl=1

        get_replicator_status $ufds_uuid
        if [[ $replicator_done != 0 ]]; then
            pct=$((($changelog_num * 100) / $totcl))
            print_log "$pct% of user data is replicated"
            print_log "The headnode is not fully usable until all users" \
                "are replicated."
            print_log "You can use 'sdc-post-upgrade -r' to monitor progress."
        fi
    fi

    echo "$(date -u "+%Y%m%dT%H%M%S") post done" \
        >>$SDC_UPGRADE_DIR/upgrade_time

    print_log ""
    print_log "The upgrade is finished"
    print_log "Note the following items:"

    dname="/var/upgrade.$(date -u "+%Y%m%dT%H%M%S")"
    mv ${SDC_UPGRADE_DIR} $dname
    # If no error setting up cloudapi, print read-only msg
    local cloudapi_failed=0
    if [ -f $dname/error_finalize.txt ]; then
        egrep -s cloudapi $dname/error_finalize.txt
        [ $? == 0 ] && cloudapi_failed=1
    fi
    if [ $cloudapi_failed == 0 ]; then
        print_log "- CloudAPI is currently in read-only mode."
        print_log "  When ready, enable read-write using sdc-post-upgrade -w"
    fi

    print_log "- Once the upgrade has been verified, run sdc-post-upgrade -c"
    print_log "  to commit to this release and reclaim the space in use for"
    print_log "  sdc-rollback. This must be done before the next upgrade."

    [ -s $dname/capi_conversion_issues.txt ] && \
        print_log "- Review CAPI issues in capi_conversion_issues.txt"

    if [[ $CONFIG_ufds_is_master == "true" ]]; then
        print_log "- If remote sites were accessing CAPI and you did not" \
                  "list all of the remote"
        print_log "  IP addresses in the capi_access file, then you must" \
                  "update the UFDS firewall"
        print_log "  rule. In the fwapi zone fix /root/fwrules.json, then run:"
        print_log "     /opt/smartdc/fwapi/bin/fwapi update -f" \
                  "/root/fwrules.json $FW_UUID"
    fi

    print_log "- The upgrade logs are in $dname"
    update_setup_state "upgrade_complete"

    if [ -f $dname/error_finalize.txt ]; then
        print_log "- ERRORS during upgrade:"
        cat $dname/error_finalize.txt | tee -a /tmp/upgrade_progress \
            >/dev/console
        print_log "You must resolve these errors before the upgrade is complete"
        print_log "Use sdc-rollback if necessary"
        exit 1
    else
        mark_as_setup
    fi
    print_log "DONE"
    cp /tmp/upgrade_progress $dname
}

reboot_zone()
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
        saw_err "Error restarting $1 zone: svcs did not completely restart"
}

# arg1 is zonename
ufds_tasks()
{
    # load config to pick up settings for newly created ufds zone
    load_sdc_config

    ufds_ip=`vmadm list -o nics.0.ip -H uuid=$1`
    client_url="ldaps://${ufds_ip}"

    #
    # If this datacenter is not a UFDS master, configure and deploy the
    # ufds-replicator service.
    #
    if [[ $CONFIG_ufds_is_master != "true" ]]; then
        local zpath=/zones/$1/root/opt/smartdc/ufds
        local tmpfile=/tmp/ufds_metadata_update.$$.json

        local service_uuid=$(sdc-sapi /services?name=ufds | json -Ha uuid)
        if [[ $? -ne 0 ]]; then
            saw_err "failed to get UFDS SAPI service"
            return
        fi

        echo "{
            \"metadata\": {
                \"REMOTE_UFDS_IP\": \"$CONFIG_ufds_remote_ip\",
                \"REMOTE_UFDS_ROOT_DN\": \"$CONFIG_ufds_ldap_root_dn\",
                \"REMOTE_UFDS_ROOT_PW\": \"$CONFIG_ufds_ldap_root_pw\"
             }
        }" > ${tmpfile}

        sdc-sapi /services/${service_uuid} -T ${tmpfile}
        [[ $? != 0 ]] && saw_err "Error updating UFDS metadata"

        rm ${tmpfile}

        #
        # The config-agent inside the UFDS zone polls SAPI every 15 seconds, so
        # it will take 15 seconds for the metadata update above to propagate
        # into the zone.  Sleep for 20 seconds to make sure the update has been
        # pushed out.
        #
        # Once the file has been updated, import and restart the ufds-replicator
        # service.
        #
        sleep 20
        cp $zpath/smf/manifests/ufds-replicator.xml.in \
            $zpath/smf/manifests/ufds-replicator.xml
        zlogin $1 svccfg import \
            /opt/smartdc/ufds/smf/manifests/ufds-replicator.xml

    else

        cp ${SDC_UPGRADE_DIR}/capi_dump/ufds.ldif /zones/$1/root
        zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
            -H ${client_url} \
            -D ${CONFIG_ufds_ldap_root_dn} \
            -w ${CONFIG_ufds_ldap_root_pw} \
            -M \
            -f /ufds.ldif >${SDC_UPGRADE_DIR}/ufds_capi_load.txt 2>&4
        local res=$?
        [[ $res != 0 ]] && saw_err "Error loading CAPI data into UFDS"
    fi

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
vmapi_tasks()
{
    cp ${SDC_UPGRADE_DIR}/mapi_dump/vmapi*.moray /zones/$1/root/root

    zlogin $1 /opt/smartdc/vmapi/bin/moray-import -f /root/vmapi_zones.moray 1>&4 2>&1
    zlogin $1 /opt/smartdc/vmapi/bin/moray-import -f /root/vmapi_vms.moray 1>&4 2>&1
    [ $? != 0 ] && \
        saw_err "Error loading VMAPI data into moray"
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
            echo "Importing image $uuid ($imageFile) into IMGAPI."
            if [[ -f $imageFile ]]; then
                echo "$image" | /opt/smartdc/bin/sdc-imgadm import -f $imageFile
                local res=$?
                if [[ $res == 0 ]]; then
                    echo "Removing image file $imageFile (no longer needed)."
                    rm $imageFile
                else
                    saw_err "Error importing image $uuid $(file) into IMGAPI."
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
    local admin_net_uuid=`zlogin $1 /opt/smartdc/napi/bin/napictl network-list | \
        json -a name uuid | nawk '{if ($1 == "admin") print $2}'`
    if [ -z "$admin_net_uuid" ]; then
        saw_err "Error, missing uuid for admin network"
        return
    fi

    for a in `cat ${SDC_UPGRADE_DIR}/allocated_addrs.txt`
    do
        local belong=""
        local z_uuid=`vmadm list -o uuid nics.0.ip=$a -H`
        # If no zone, it must be one of the binder IPs we set aside
        if [ -n "$z_uuid" ]; then
            belong="belongs_to_uuid=\"$z_uuid\" belongs_to_type=zone"
        else
            z_uuid="binder"
        fi

        zlogin $1 /opt/smartdc/napi/bin/napictl ip-update $admin_net_uuid $a \
            owner_uuid="${CONFIG_ufds_admin_uuid}" \
	    $belong reserved=true 1>&4 2>&1
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

    local ips="ip $portal_ip"
    if [ -f ${SDC_UPGRADE_DIR}/capi_access ]; then
        for i in `cat ${SDC_UPGRADE_DIR}/capi_access`
        do
            ips="$ips OR ip $i"
        done
    fi

    netmask_to_cidr $CONFIG_admin_netmask
    cat <<-FW_DONE >/zones/$fwapi_uuid/root/root/fwrules.json
	{ "enabled": true,
	  "owner_uuid": "${CONFIG_ufds_admin_uuid}",
	  "rule": "FROM (subnet ${CONFIG_admin_network}/$cidr OR $ips) TO vm $ufds_uuid ALLOW tcp (port 8080 AND port 636)"
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
    local service_uuid=$(sdc-sapi /services?name=cloudapi | json -Ha uuid)
    if [[ $? -ne 0 ]]; then
        saw_err "failed to get CloudAPI SAPI service"
        return
    fi
    local tmpfile=/tmp/cloudapi_metadata_changes.$$.json

    if [[ $CONFIG_ufds_is_master != "true" ]]; then
        # pickup config
        load_sdc_config

        echo "{
            \"metadata\": {
                \"REMOTE_UFDS_IP\": \"$CONFIG_ufds_remote_ip\",
                \"REMOTE_UFDS_ROOT_DN\": \"$CONFIG_ufds_ldap_root_dn\",
                \"REMOTE_UFDS_ROOT_PW\": \"$CONFIG_ufds_ldap_root_pw\"
             }
        }" > ${tmpfile}

        sdc-sapi /services/${service_uuid} -T ${tmpfile}
        [[ $? != 0 ]] && saw_err "Error updating CloudAPI metadata"

        rm ${tmpfile}
    fi

    zlogin $1 zfs set mountpoint=/cloudapi/data zones/$1/data

    # Parts of the 6.5.x backup are compatible with the 7.0 cloudapi
    # configuration, but not all, so restore what we can and convert the rest.

    local bdir=${SDC_UPGRADE_DIR}/bu.tmp/cloudapi

    # The plugin and ssl config is compatible
    if [[ -d "$bdir/plugins" ]]; then
        for i in `ls $bdir/plugins`
        do
            # Only copy non-existant plugins. machine_email and capi_limits
            # have been upgraded to work with vmapi instead of mapi.
            if [[ ! -f /zones/$1/root/opt/smartdc/cloudapi/plugins/$i && \
               ! -d /zones/$1/root/opt/smartdc/cloudapi/plugins/$i ]]; then
                mkdir -p /zones/$1/root/cloudapi/data/plugins
                cp -pr $bdir/plugins/$i \
                    /zones/$1/root/cloudapi/data/plugins
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
        var tmpPath = process.argv[3];

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
            p.name = "../../../../cloudapi/data/plugins/" +
                path.basename(p.plugin);
            delete p.plugin;
            cfg.plugins.push(p);
        });

        var changes = {};
        changes.metadata = {};
        changes.metadata.CLOUDAPI_PLUGINS = JSON.stringify(cfg.plugins);
        changes.metadata.CLOUDAPI_DATACENTERS = JSON.stringify(cfg.datacenters);

        fs.writeFileSync(tmpPath, JSON.stringify(changes));
    ' $ocfg $cfgfile $tmpfile

    sdc-sapi /services/${service_uuid} -T ${tmpfile}
    [[ $? != 0 ]] && saw_err "Error updating CloudAPI plugins and datacenters"
    rm -f $tmpfile

    # Put CloudAPI into read-only mode
    echo "{
        \"metadata\": {
            \"CLOUDAPI_READONLY\": true
         }
    }" > ${tmpfile}

    sdc-sapi /services/${service_uuid} -T ${tmpfile}
    [[ $? != 0 ]] && saw_err "Error updating CloudAPI mode"
    rm ${tmpfile}

    # Reboot the zone with the new config data
    zoneadm -z $1 reboot
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

"napi") echo "$2" >${SDC_UPGRADE_DIR}/napi_zonename.txt;;

"vmapi") echo "$2" >${SDC_UPGRADE_DIR}/vmapi_zonename.txt;;
esac

exit 0
