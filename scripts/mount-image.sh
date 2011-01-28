#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#

usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
image="${usbmnt}/platform/i86pc/amd64/boot_archive"
mnt=/image

function fatal
{
	echo "`basename $0`: $*" > /dev/fd/2
	exit 1
}


if [[ ! -d $mnt ]]; then
	mkdir $mnt || fatal "could not make $mnt"
fi

USBKEYS=`/usr/bin/disklist -a`
for key in ${USBKEYS}; do
    if [[ `/usr/sbin/fstyp /dev/dsk/${key}p0:1` == 'pcfs' ]]; then
        /usr/sbin/mount -F pcfs -o foldcase /dev/dsk/${key}p0:1 ${usbmnt};
        if [[ $? == "0" ]]; then
            if [[ ! -f ${usbmnt}/.joyliveusb ]]; then
                /usr/sbin/umount ${usbmnt};
            else
                break;
            fi
        fi
    fi
done

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
