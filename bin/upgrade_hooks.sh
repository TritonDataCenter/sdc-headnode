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

BASH_XTRACEFD=4
set -o xtrace

. /lib/sdc/config.sh

saw_err()
{
    echo "    $1" >> /var/upgrade_headnode/error_finalize.txt
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
    if [ -f /var/upgrade_headnode/error_finalize.txt ]; then
        echo "ERRORS during upgrade:" >/dev/console
        cat /var/upgrade_headnode/error_finalize.txt >/dev/console
        echo "You must resolve these errors before the headnode is usable" \
            >/dev/console
        fatal="true"
    fi

    # XXX Install old platforms used by CNs

    mv /var/upgrade_headnode /var/upgrade.$(date -u "+%Y%m%dT%H%M%S")

    [ -n "$fatal" ] && exit 1
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

"post") post_tasks;;

"ufds") ufds_tasks $2;;
esac

exit 0
