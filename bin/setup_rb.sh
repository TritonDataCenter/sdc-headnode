#!/bin/bash
#
# Copyright (c) 2012, Joyent, Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin:/image/usr/sbin:/opt/smartdc/bin:/smartdc/bin
export PATH

ZONES6X="adminui assets billapi ca cloudapi dhcpd mapi portal rabbitmq riak"

fatal()
{
    msg=$1

    echo "ERROR: ${msg}" >/dev/stderr
    exit 1
}

# We have our own mount_usb since we need to mount the key without foldcase
# in order to make a proper backup.
mount_usb()
{
    mkdir -p /mnt/usbkey
    USBKEYS=`/usr/bin/disklist -a`
    for key in ${USBKEYS}; do
        if [[ `/usr/sbin/fstyp /dev/dsk/${key}p0:1` == 'pcfs' ]]; then
            /usr/sbin/mount -F pcfs -o noatime /dev/dsk/${key}p0:1 /mnt/usbkey
            if [[ $? == "0" ]]; then
                if [[ ! -f /mnt/usbkey/.joyliveusb ]]; then
                    /usr/sbin/umount /mnt/usbkey
                else
                    break;
                fi
            fi
    fi
    done

    mount | grep "^/mnt/usbkey" >/dev/null 2>&1 || \
        fatal "/mnt/usbkey is not mounted"
}

[ -d /var/usb_rollback ] && fatal "rollback is already in place"

CAPI_FOUND=0
for z in `zoneadm list -cp | cut -f2 -d:`
do
	if [[ "$z" == "capi" ]]; then
		CAPI_FOUND=1
		ZONES6X="$ZONES6X capi"
		capi_dds=`zfs list -o name -H | egrep "^zones/capi/capi-app"`
	fi
done

# Backup usbkey to local disk
# The 6.5.x sdc-backup doesn't support '-U -' so we have to do this ourselves
mount_usb
mkdir /var/usb_rollback
echo "copying USB key for rollback"
(cd /mnt/usbkey; tar cbf 512 - .) | (cd /var/usb_rollback; tar xbf 512 -)
if [ $? != 0 -o ! -f /var/usb_rollback/version ]; then
    rm -rf /var/usb_rollback
    umount /mnt/usbkey
    fatal "error copying USB key for rollback"
fi
umount /mnt/usbkey

echo "snapshotting the datasets"

# snapshot existing datasets

# We can't rollback the top-level ds on a live system.
# Save a list of the datasets and files so we could remove the new ones on
# rollback.
zfs list -H -o name -s name >/var/usb_rollback/ds_orig
ls /zones >/var/usb_rollback/files_orig

zfs snapshot -r zones@rollback || fatal "failed to snapshot zones"
zfs destroy zones@rollback
zfs destroy zones/dump@rollback
zfs destroy zones/swap@rollback

# For the core zone datasets, delete snapshot, clear the mountpoint and
# rename the ds so it won't conflict with the upgrade

# The delegated datasets need some special handling
# We need to disable the zoned attribute before we can rename.
# We'll delete the snapshots for these at the same time.
adminui_dds=`zfs list -o name -H | egrep "^zones/adminui/adminui-app"`
mapi_dds=`zfs list -o name -H | egrep "^zones/mapi/mapi-app"`

zfs set zoned=off $adminui_dds
zfs set zoned=off zones/adminui/adminui-data
zfs set zoned=off zones/ca/ca-data
zfs set zoned=off $mapi_dds
zfs set zoned=off zones/mapi/mapi-data

zfs destroy $adminui_dds@rollback
zfs destroy zones/adminui/adminui-data@rollback
zfs destroy zones/ca/ca-data@rollback
zfs destroy $mapi_dds@rollback
zfs destroy zones/mapi/mapi-data@rollback

# delete snapshot on the origin dataset for all of the core zones
origin_ds=`zfs list -o origin -H zones/mapi | \
    nawk '{split($1, a, "@"); print a[1]}'`
zfs destroy ${origin_ds}@rollback

if [[ $CAPI_FOUND == 1 ]]; then
	zfs set zoned=off $capi_dds
	zfs set zoned=off zones/capi/capi-data
	zfs destroy $capi_dds@rollback
	zfs destroy zones/capi/capi-data@rollback
fi

for z in $ZONES6X
do
	zfs destroy zones/${z}@rollback
	zfs destroy zones/${z}/cores@rollback

	zfs set mountpoint=none zones/${z}/cores
	zfs set mountpoint=none zones/${z}

	zfs rename zones/${z} zones/${z}_rollback
	rmdir /zones/${z} 2>/dev/null
done

echo "done"

exit 0
