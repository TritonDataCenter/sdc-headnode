#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

mnt=/image
image="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/joyent)/platform/i86pc/amd64/boot_archive"

if ! mount | grep ^"${mnt} " > /dev/null ; then 
	fatal "cannot find image mounted at $mnt"
fi

file=$(mount | grep ^"${mnt} " | nawk '{ print $3 }')

echo -n "Unmounting $mnt ... "

if ! umount $mnt/usr ; then
	fatal "could not unmount $mnt/usr"
fi

if ! umount $mnt ; then
	fatal "could not unmount $mnt"
fi

echo "done."
