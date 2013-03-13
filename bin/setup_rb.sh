#!/bin/bash
#
# Copyright (c) 2013, Joyent, Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin:/image/usr/sbin:/opt/smartdc/bin:/smartdc/bin
export PATH

# Snapshot these datasets instead of renaming
SS="zones/var zones/opt zones/usbkey zones/config zones/portal"
# Skip renaming these datasets
SKIP="$SS zones zones/swap zones/dump zones/cores zones/pre-upgrade"

declare -A SKIP_DS=()
for i in $SKIP
do
        SKIP_DS[$i]=1
done

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

# Cleanup to a known state, but only if we're fresh or have rolled back.
# We don't do all of this cleanup when we rollback, in case something goes
# wrong during that process, but now we are ready to try again.
# Anything in the rollback dir implies we haven't rolled back or commited.
exists=`zfs list -o name -H zones/pre-upgrade 2>/dev/null`
if [ -n "$exists" ]; then
    # This dataset is normally not present but we have rolled back

    nsubs=`zfs list -o name -H 2>/dev/null | egrep "^zones/pre-upgrade" | wc -l`
    [ $nsubs -gt 1 ] && fatal "rollback is already in place"
    zfs destroy zones/pre-upgrade 2>/dev/null 2>&1
fi
rm -rf /var/usb_rollback

zfs create -o mountpoint=legacy zones/pre-upgrade

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

# We can't rollback the top-level ds on a live system.
# Save a list of existing datasets and manifest files so we can remove any new
# ones on rollback. There can be lots of extra stuff that sysadmins have put
# into /zones so we just worry about /zones/manifests.
zfs list -H -o name -s name >/var/usb_rollback/ds_orig
(cd /zones/manifests; find . -mount | cpio -o -O /var/usb_rollback/files_orig)

echo "snapshotting datasets"

# snapshot SS datasets
for d in $SS
do
	zfs snapshot ${d}@rollback
done

echo "renaming datasets"

LIST=`zfs list -o name -H`

for i in $LIST
do
        [ -n "${SKIP_DS[$i]}" ] && continue
        zfs set canmount=off $i
        # Don't need to remember zoned attr since gets set automatically on
        # delegated datasets if we have to rollback.
        zoned=`zfs get -o value -H zoned $i`
        [ "$zoned" == "on" ] && zfs set zoned=off $i
done

for i in $LIST
do
        [ -n "${SKIP_DS[$i]}" ] && continue

        # only need to rename top-level datasets
        levels=`echo $i | nawk '{cnt=gsub("/", "/"); print cnt}'`
        [ $levels -ne 1 ] && continue

        bname=${i##*/}
        zfs rename $i zones/pre-upgrade/$bname
done

# convert to new-style GZ cores dataset
zfs destroy -r zones/cores
zfs create -o compression=gzip -o mountpoint=none zones/cores
zfs create -o quota=100g -o mountpoint=/zones/global/cores zones/cores/global

echo "done"

exit 0
