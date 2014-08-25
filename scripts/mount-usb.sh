#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

# BASHSTYLED
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"

USBKEYS=`/usr/bin/disklist -a`
for key in ${USBKEYS}; do
    if [[ `/usr/sbin/fstyp /dev/dsk/${key}p1` == 'pcfs' ]]; then
        /usr/sbin/mount -F pcfs -o foldcase,noatime /dev/dsk/${key}p1 \
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
