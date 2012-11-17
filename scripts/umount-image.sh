#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

current_image=$(uname -v | cut -d '_' -f2)
mnt=/image
usb="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcopy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
image_subdir="/os/${current_image}/platform/i86pc/amd64"
image="${usb}${image_subdir}/boot_archive"

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

cp ${image} "${usbcopy}${image_subdir}"
digest -a sha1 ${image} > "${image}.hash"
cp "${image}.hash" "${usbcopy}${image_subdir}"

if ! umount $usb ; then
    fatal "could not unmount $usb"
fi
echo "done."
