#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2019, Joyent, Inc.
#

function fatal
{
    echo "`basename $0`: $*" >&2 
    exit 1
}

current_image=$(uname -v | cut -d '_' -f2)
mnt=/image
# BEGIN BASHSTYLED
usbcopy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
# END BASHSTYLED
image_subdir="/os/${current_image}/platform/i86pc/amd64"
image="${usb}${image_subdir}/boot_archive"
writable_usr=0

if ! mount | grep ^"${mnt} " > /dev/null ; then
    fatal "cannot find image mounted at $mnt"
fi

file=$(mount | grep ^"${mnt} " | nawk '{ print $3 }')

echo -n "Unmounting $mnt ... "

if mount | grep ^/image/usr | grep /var/tmp/usr.lgz > /dev/null; then
    writable_usr=1
fi

if ! umount $mnt/usr ; then
    fatal "could not unmount $mnt/usr"
fi

if [[ ${writable_usr} == 1 ]]; then
    lofiadm -C /var/tmp/usr.lgz || fatal "could not recompress /usr"
    rm -f $mnt/usr.lgz || fatal "could not remove old ${mnt}/usr.lgz"
    sync
    cp /var/tmp/usr.lgz $mnt/usr.lgz || \
        fatal "could not copy usr.lgz to $mnt"
    rm -f /var/tmp/usr.lgz \
        || echo "Warning: could not remove /var/tmp/usr.lgz" >&2
    sync
fi

if ! umount $mnt ; then
    fatal "could not unmount $mnt"
fi

cp ${image} "${usbcopy}${image_subdir}"
digest -a sha1 ${image} > "${image}.hash"
cp "${image}.hash" "${usbcopy}${image_subdir}"

/opt/smartdc/bin/sdc-usbkey unmount
[[ $? != 0 ]] && fatal "could not unmount USB key"

echo "done."
