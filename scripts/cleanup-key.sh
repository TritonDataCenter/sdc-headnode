#!/usr/bin/bash

usbmnt=/mnt/usbkey

/usbkey/scripts/mount-usb.sh

# cleanup old images from the USB key
cnt=$(ls -d ${usbmnt}/os/* | wc -l)
if [ $cnt -gt 2 ]; then
	# delete all but the last two images (current and previous)
	del_cnt=$(($cnt - 2))
	for i in $(ls -d ${usbmnt}/os/* | head -$del_cnt)
	do
		echo "removing $i"
		rm -rf $i
	done
fi

umount /mnt/usbkey
