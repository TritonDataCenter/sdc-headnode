#!/bin/bash
#
# Copyright (c) 2012 Joyent Inc., All rights reserved.
#

set -o errexit
set -o pipefail
#set -o xtrace

version=$1
if [[ -z ${version} ]]; then
    echo "Usage: $0 <platform buildstamp>"
    echo "(eg. '$0 20110318T170209Z')"
    exit 1
fi

current_version=$(uname -v | cut -d '_' -f 2)

mounted="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

function onexit
{
    if [[ ${mounted} == "true" ]]; then
        echo "==> Unmounting USB Key"
        umount /mnt/usbkey
    fi

    echo "==> Done!"
}

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

trap onexit EXIT

if [[ ! -d ${usbmnt}/os/${version} ]]; then
    echo "==> FATAL ${usbmnt}/os/${version} does not exist."
    exit 1
fi

echo "==> Creating new menu.lst"
cat ${usbmnt}/boot/grub/menu.lst.tmpl | sed \
    -e "s|/PLATFORM/|/os/${version}/platform/|" \
    -e "s|/PREV_PLATFORM/|/os/${current_version}/platform/|" \
    -e "s|PREV_PLATFORM_VERSION|${current_version}|" \
    -e "s|^#PREV ||" \
    > ${usbmnt}/boot/grub/menu.lst

echo "==> Updating cnapi"
. /lib/sdc/config.sh
load_sdc_config

uuid=`curl -s -u admin:${CONFIG_cnapi_root_pw} \
    http://${CONFIG_cnapi_admin_ips}//servers | json | nawk '{
        if ($1 == "\"headnode\":" && $2 == "\"true\",")
            found=1
        if (found && $1 == "\"uuid\":") {
            print substr($2, 2, length($2) - 3)
            found=0
        }
    }' 2>/dev/null`

if [[ -z "${uuid}" ]]; then
    echo "==> FATAL unable to determine headnode UUID from cnapi."
    exit 1
fi

curl -s -u admin:${CONFIG_cnapi_root_pw} \
    http://${CONFIG_cnapi_admin_ips}//servers/${uuid} \
    -X POST -d boot_platform=${version} >/dev/null 2>&1

exit 0
