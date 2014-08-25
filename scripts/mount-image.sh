#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Usage:
#
#  mount-image [-w]
#
#  Note: With -w /image/usr will be mounted r/w, with or without -w you
#  need to use umount-image.sh when you're done to write back the changes.
#

current_image=$(uname -v | cut -d '_' -f2)
# BASHSTYLED
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
image="${usbmnt}/os/${current_image}/platform/i86pc/amd64/boot_archive"
mnt=/image
writable_usr=0

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}

if [[ $1 == "-w" ]]; then
	writable_usr=1
fi

if [[ ! -d $mnt ]]; then
	mkdir $mnt || fatal "could not make $mnt"
fi

# BASHSTYLED
usbcp="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

mount | grep "^${usbmnt}" >/dev/null 2>&1 || bash $usbcp/scripts/mount-usb.sh

mount | grep "^${usbmnt}" >/dev/null 2>&1 || fatal "${usbmnt} is not mounted"

if [[ ! -f $image ]]; then
	fatal "could not find image file $image"
fi

echo -n "Mounting archive on $mnt ... "
mount -F ufs $image $mnt || fatal "could not mount image $image"
echo "done."
echo -n "Mounting archived usr on (writable=${writable_usr}) ${mnt}/usr ... "
if [[ ${writable_usr} == 1 ]]; then
	[[ -e /var/tmp/usr.lgz ]] && fatal \
	"fatal: /var/tmp/usr.lgz already exists, please remove and try again."
	cp /image/usr.lgz /var/tmp/usr.lgz || \
	    fatal "failed to copy to /var/tmp/"
	lofiadm -U /var/tmp/usr.lgz || \
	    fatal "failed to uncompress /var/tmp/usr.lgz"
	mount -F ufs -o rw /var/tmp/usr.lgz $mnt/usr || \
	    fatal "could not mount usr /var/tmp/usr.lgz"
else
	mount -F ufs -o ro $mnt/usr.lgz $mnt/usr || \
	    fatal "could not mount usr $mnt/usr.lgz"
fi
echo "done."

echo "Image mounted; use umount-image.sh to unmount"
