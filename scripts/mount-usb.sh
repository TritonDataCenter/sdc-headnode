#!/usr/bin/bash

usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"

USBKEYS=`/usr/bin/disklist -a`
for key in ${USBKEYS}; do
    if [[ `/usr/sbin/fstyp /dev/dsk/${key}p0:1` == 'pcfs' ]]; then
        /usr/sbin/mount -F pcfs -o foldcase,noatime /dev/dsk/${key}p0:1 \
            ${usbmnt};
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


