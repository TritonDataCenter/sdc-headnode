#!/usr/bin/bash

usbmnt=/mnt/usbkey
cache=/usbkey

cleanup_cache=0
while getopts "c" opt
do
	case "$opt" in
		c)	cleanup_cache=1;;
	esac
done
shift $(($OPTIND - 1))

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

if [ ${cleanup_cache} -eq 1 ]; then
    # cleanup old images from the on-disk cache
    # we have to also account for the "latest" link
    cnt=$(ls -d ${cache}/os/2* | wc -l)
    if [ $cnt -gt 2 ]; then
	# delete all but the last two images (current and previous)
	del_cnt=$(($cnt - 2))
	for i in $(ls -d ${cache}/os/2* | head -$del_cnt)
	do
		echo "removing $i"
		rm -rf $i
	done
    fi
fi
