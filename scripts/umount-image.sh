#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
#

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

mnt=/image
image=`dirname $0`/../platform/i86pc/amd64/boot_archive

if ! mount | grep ^"${mnt} " > /dev/null ; then 
	fatal "cannot find image mounted at $mnt"
fi

file=$(mount | grep ^"${mnt} " | nawk '{ print $3 }')

echo -n "Unmounting $mnt ... "

if ! umount $mnt ; then
	fatal "could not unmount $mnt"
fi

echo "done."

echo -n "Compressing `basename $image` ... "
gzip -c $file > $image || fatal "could not compress $image"
echo "done."

