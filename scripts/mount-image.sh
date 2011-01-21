#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#

usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/joyent)"
image="${usbmnt}/platform/i86pc/amd64/boot_archive"
tmp=/var/tmp/boot_archive.uncompressed.$$
mnt=/image

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

mount | grep "^${usbmnt}" >/dev/null 2>&1 || fatal "${usbmnt} is not mounted"

if [[ ! -d $mnt ]]; then
	mkdir $mnt || fatal "could not make $mnt"
fi

if [[ ! -f $image ]]; then
	fatal "could not find image file $image"
fi

echo -n "Uncompressing `basename $image` ... "
gzip -c -d $image > $tmp || fatal "could not uncompress $image"
echo "done."

echo -n "Mounting uncompressed archive on $mnt ... "
mount -F ufs $tmp $mnt || fatal "could not mount uncompressed image $tmp"
echo "done."

echo "Image mounted; use umount-image.sh to unmount"
