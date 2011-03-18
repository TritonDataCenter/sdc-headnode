#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

set -o errexit
set -o pipefail
#set -o xtrace

input=$1
if [[ -z ${input} ]]; then
    echo "Usage: $0 <platform URI>"
    echo "(URI can be file:///, http://, or anything curl supports)"
    exit 1
fi

mounted="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

# this should result in something like 20110318T170209Z
version=$(basename "${input}" | sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")

if [[ -d ${usbmnt}/os/${version} ]]; then
    echo "FATAL: ${usbmnt}/os/${version} already exists."
    exit 1
fi

echo "==> Unpacking ${version} to ${usbmnt}/os"
curl --progress -k ${input} \
    | (mkdir -p ${usbmnt}/os/${version} \
    && cd ${usbmnt}/os/${version} \
    && gunzip | tar -xf - 2>/tmp/install_platform.log \
    && mv platform-* platform
)

if [[ -f ${usbmnt}/os/${version}/platform/root.password ]]; then
     mv -f ${usbmnt}/os/${version}/platform/root.password \
         ${usbmnt}/private/root.password.${version}
fi

echo "==> Copying ${version} to ${usbcpy}/os"
(cd ${usbmnt}/os && rsync -a ${version}/ ${usbcpy}/os/${version})

if [[ ${mounted} == "true" ]]; then
    echo "==> Unmounting USB Key"
    umount /mnt/usbkey
fi

echo "==> Done!"

exit 0
