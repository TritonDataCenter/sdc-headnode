#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#

current_image=$(uname -v | cut -d '_' -f2)
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
image="${usbmnt}/os/${current_image}/platform/i86pc/amd64/boot_archive"
mnt=/image

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}


if [[ ! -d $mnt ]]; then
	mkdir $mnt || fatal "could not make $mnt"
fi

usbcp="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

mount | grep "^${usbmnt}" >/dev/null 2>&1 || bash $usbcp/scripts/mount-usb.sh

mount | grep "^${usbmnt}" >/dev/null 2>&1 || fatal "${usbmnt} is not mounted"

if [[ ! -f $image ]]; then
	fatal "could not find image file $image"
fi

echo -n "Mounting archive on $mnt ... "
mount -F ufs $image $mnt || fatal "could not mount image $image"
echo
echo -n "Mounting archived usr on $mnt/usr ... "
mount -F ufs -o ro $mnt/usr.lgz $mnt/usr || \
    fatal "could not mount usr $mnt/usr.lgz"
echo
echo "done."

echo "Image mounted; use umount-image.sh to unmount"
