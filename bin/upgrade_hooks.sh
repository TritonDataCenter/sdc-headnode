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
set -o xtrace

. /lib/sdc/config.sh

# time to wait for each zone to setup (in seconds)
ZONE_SETUP_TIMEOUT=180

# We have to install the extra zones in dependency order
EXTRA_ZONES="billapi ca dcapi redis adminui amon cloudapi portal"

saw_err()
{
    echo "    $1" >> /var/upgrade_headnode/error_finalize.txt
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

    for i in $EXTRA_ZONES
    do
        [[ ${existing_zones[$i]} == 1 ]] && continue

        echo "creating zone $i..." >/dev/console
        sdc-role create $i 1>&4 2>&1
        if [ $? != 0 ]; then
            saw_err "Error creating $i zone"
            mv /tmp/payload.* /var/upgrade_headnode
            mv /tmp/provision.* /var/upgrade_headnode
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
            echo "upgrading zone $i..." >/dev/console
            /var/upgrade_headnode/upgrade_hooks.sh $i ${new_uuid} \
              4>/var/upgrade_headnode/finish_${i}.log
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

    echo "Installing images" >/dev/console
    for i in /usbkey/datasets/*.dsmanifest
    do
        bname=${i##*/}
        echo "Import dataset $bname" >/dev/console

        bzname=`nawk '{
            if ($1 == "\"path\":") {
                # strip quotes and colon
                print substr($2, 2, length($2) - 3)
                exit 0
            }
        }' $i`

        if [ ! -f /usbkey/datasets/$bzname ]; then
            echo "Skipping $i, no image file in /usbkey/datasets" >/dev/console
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
    echo "Upgrade: waiting for all svcs to be ready..." >/dev/console
    loops=0
    while [[ -n $(svcs -x) && $loops -lt ${ZONE_SETUP_TIMEOUT} ]]
    do
        sleep 1
        loops=$((${loops} + 1))
    done

    if [[ ${loops} -ge ${ZONE_SETUP_TIMEOUT} ]]; then
        saw_err "Error global zone: svcs timed out"
        echo "Upgrade: ERROR global zone: svcs timed out" >/dev/console
        exit 1
    fi

    echo "Upgrade: all svcs are ready, continuing..." >/dev/console

    create_extra_zones

    dname="/var/upgrade.$(date -u "+%Y%m%dT%H%M%S")"

    # XXX Install old platforms used by CNs

    mv /var/upgrade_headnode $dname
    echo "The upgrade is finished" >/dev/console
    echo "The upgrade logs are in $dname" >/dev/console

    if [ -f $dname/error_finalize.txt ]; then
        echo "ERRORS during upgrade:" >/dev/console
        cat $dname/error_finalize.txt >/dev/console
        echo "You must resolve these errors before the headnode is usable" \
            >/dev/console
        exit 1
    fi
}

# arg1 is zonename
ufds_tasks()
{
    # load config to pick up settings for newly created ufds zone
    load_sdc_config

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

    cp /var/upgrade_headnode/capi_dump/ufds.ldif /zones/$1/root
    zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
        -H ${client_url} \
        -D ${CONFIG_ufds_ldap_root_dn} \
        -w ${CONFIG_ufds_ldap_root_pw} \
        -f /ufds.ldif 1>&4 2>&1
    [ $? != 0 ] && saw_err "Error loading CAPI data into UFDS"
}

case "$1" in
"pre") pre_tasks;;

"post") echo "Finishing the upgrade in the background" >/dev/console
        /var/upgrade_headnode/upgrade_hooks.sh "post_bg" \
            4>/var/upgrade_headnode/finish_post.log &
        ;;

"post_bg") post_tasks;;

"ufds") ufds_tasks $2;;
esac

exit 0
