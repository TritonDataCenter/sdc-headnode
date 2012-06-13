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
    # XXX Install old platforms used by CNs

    mv /var/upgrade_headnode /var/upgrade.$(date -u "+%Y%m%dT%H%M%S")
}

case "$1" in
"pre") pre_tasks;;

"post") post_tasks;;
esac

exit 0
