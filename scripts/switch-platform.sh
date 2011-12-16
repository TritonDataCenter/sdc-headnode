#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
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

exit 0
