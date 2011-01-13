#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
#

image=`dirname $0`/../platform/i86pc/amd64/boot_archive
tmp=/var/tmp/boot_archive.uncompressed.$$
mnt=/image

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

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

echo "Image mounted; use umount-image to unmount"
