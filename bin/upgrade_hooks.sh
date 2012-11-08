#!/bin/bash
#
# Copyright (c) 2012, Joyent, Inc., All rights reserved.
#
# These upgrade hooks are called from headnode.sh during the first boot
# after we initiated the upgrade in order to complete the upgrade steps.
#
# The "pre" and "post" hooks are called before headnode does any setup
# and after the setup is complete.
#
# The role-specific hooks are called after each zone role has been setup.
#

unset LD_LIBRARY_PATH
# /image/usr/sbin is here so we pickup vmadm on 6.5
PATH=/usr/bin:/usr/sbin:/opt/smartdc/bin:/smartdc/bin
export PATH

BASH_XTRACEFD=4
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

. /lib/sdc/config.sh

# time to wait for each zone to setup (in seconds)
ZONE_SETUP_TIMEOUT=180

SDC_UPGRADE_DIR=/var/upgrade_headnode

# We have to install the extra zones in dependency order
EXTRA_ZONES="keyapi sdcsso usageapi ca adminui amon cloudapi portal"

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
                curl -i -s -u admin:${CONFIG_vmapi_http_admin_pw} \
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

pre_tasks()
{
    if [[ ! -f /var/db/imgadm/sources.list ]]; then
        # For now we initialize with the global one since we don't have a local
        # imgapi yet.
        mkdir -p /var/db/imgadm
        echo "https://datasets.joyent.com/datasets/" \
            > /var/db/imgadm/sources.list
        imgadm update
    fi

    print_log "Installing images"
    for i in /usbkey/datasets/*.dsmanifest
    do
        bname=${i##*/}
        print_log "Import dataset $bname"

        bzname=`nawk '{
            if ($1 == "\"path\":") {
                # strip quotes and colon
                print substr($2, 2, length($2) - 3)
                exit 0
            }
        }' $i`

        if [ ! -f /usbkey/datasets/$bzname ]; then
            print_log "Skipping $i, no image file in /usbkey/datasets"
            continue
        fi

        imgadm install -m $i -f /usbkey/datasets/$bzname
    done
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
        print_log "Upgrade: ERROR global zone: svcs timed out"
        exit 1
    fi

    print_log "Upgrade: all svcs are ready, continuing..."

    # load config to pick up latest settings
    load_sdc_config

    create_extra_zones

    dname="/var/upgrade.$(date -u "+%Y%m%dT%H%M%S")"

    # XXX Install old platforms used by CNs

    mv ${SDC_UPGRADE_DIR} $dname
    print_log "The upgrade is finished"
    print_log "The upgrade logs are in $dname"

    if [ -f $dname/error_finalize.txt ]; then
        print_log "ERRORS during upgrade:"
        cat $dname/error_finalize.txt | tee -a /tmp/upgrade_progress \
            >/dev/console
        print_log "You must resolve these errors before the headnode is usable"
        exit 1
    fi
}

# This function is used to restore a zone role when the 6.5.x backup is
# compatible with the 7.0 role configuration.
#
# arg1 is role
# arg2 is zonename
compatible_restore_task()
{
    # We're going to replace the config files, so halt the zone
    shutdown_zone $2

    /usbkey/zones/$1/restore $2 ${SDC_UPGRADE_DIR}/bu.tmp 1>&4 2>&1
    [ $? != 0 ] && saw_err "Error restoring $1 zone $2"

    # Boot the zone with the new config data
    zoneadm -z $2 boot
}

# arg1 is zonename
ufds_tasks()
{
    # load config to pick up settings for newly created ufds zone
    load_sdc_config

    [[ $CONFIG_ufds_is_local != "true" ]] && return

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
        -f /ufds.ldif 1>&4 2>&1
    # err 68 means it already exists - allow this in case we're re-running
    local res=$?
    [[ $res != 0 && $res != 68 ]] && saw_err "Error loading CAPI data into UFDS"

    cp ${SDC_UPGRADE_DIR}/mapi_dump/mapi-ufds.ldif /zones/$1/root
    zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
        -H ${client_url} \
        -D ${CONFIG_ufds_ldap_root_dn} \
        -w ${CONFIG_ufds_ldap_root_pw} \
        -f /mapi-ufds.ldif 1>&4 2>&1
    res=$?
    [[ $res != 0 && $res != 68 ]] && saw_err "Error loading MAPI data into UFDS"
}

case "$1" in
"pre") pre_tasks;;

"post") print_log "Finishing the upgrade in the background"
        ${SDC_UPGRADE_DIR}/upgrade_hooks.sh "post_bg" \
            4>${SDC_UPGRADE_DIR}/finish_post.log &
        ;;

"post_bg") post_tasks;;

"cloudapi")
    # Currently a simple restore is fine for cloudapi and the 7.0 restore is
    # compatible with the 6.5.x backup, but if we need to do any transforms on
    # the 6.5.x backup data, we should split out a separate cloudapi_tasks
    # function.
    compatible_restore_task "cloudapi" $2
    ;;

"portal")
    # Currently a simple restore is fine for portal and the 7.0 restore is
    # compatible with the 6.5.x backup, but if we need to do any transforms on
    # the 6.5.x backup data, we should split out a separate portal_tasks
    # function.
    compatible_restore_task "portal" $2
    ;;

"ufds") ufds_tasks $2;;
esac

exit 0
