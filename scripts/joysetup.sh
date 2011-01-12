#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin
export PATH

ZPOOL=zones

CONFDS=$ZPOOL/config
OPTDS=$ZPOOL/opt
VARDS=$ZPOOL/var
USBKEYDS=$ZPOOL/usbkey
SWAPVOL=${ZPOOL}/swap

set -o errexit
set -o pipefail
set -o xtrace

#
# Load command line arguments in the form key=value (eg. swap=4g)
#
for p in $*; do
  k=$(echo "${p}" | cut -d'=' -f1)
  v=$(echo "${p}" | cut -d'=' -f2-)
  export arg_${k}=${v}
done

fatal()
{
    echo "Error: $1" >> /dev/console
    exit 1
}

#
# find disk(s) - either 1 disk or multiple - maybe raidz?
#
create_zpool()
{
    disks=''

    if /usr/bin/bootparams | grep "headnode=true"; then
        for disk in `/usr/bin/disklist -n`; do
            # Only include disks that aren't mounted (so we skip USB Key)
            if ( ! grep ${disk} /etc/mnttab ); then
                disks="${disks} ${disk}"
            fi
        done
    else
        disks=`/usr/bin/disklist -n`
    fi

    disk_count=$(echo "${disks}" | wc -w | tr -d ' ')

    if [ ${disk_count} -lt 1 ]; then
        # XXX what if no disks found?
        fatal "no disks found, can't create zpool"
    elif [ ${disk_count} -eq 1 ]; then
        # create a zpool with a single disk
        zpool create ${ZPOOL} ${disks}
    else
        # if more than one disk, create a raidz zpool
        zpool create ${ZPOOL} raidz ${disks}
    fi
}

#
# XXX - may want to tweak this algorithm a bit (needs to work in production
# and on coal)
# Create a dump device zvol on persistent storage.  Make it either 5% of the
# base ZFS dataset size or 4GB, whichever is less.
#
create_dump()
{
    # Get avail zpool size - this assumes we're not using any space yet.
    base_size=`zfs get -H -p -o value available $ZPOOL`
    # Convert to MB
    base_size=`expr $base_size / 1000000`
    # Calculate 5% of that
    base_size=`expr $base_size / 20`
    # Cap it at 4GB
    [ ${base_size} -gt 4096 ] && base_size=4096

    # Create the dump zvol
    zfs create -V ${base_size}mb ${ZPOOL}/dump || \
      fatal "failed to create the dump zvol"
}

#
# Setup the persistent datasets on the zpool.
#
setup_datasets()
{
    echo -n "Making dump zvol... " >>/dev/console
    create_dump
    echo "done." >>/dev/console

    echo -n "Initializing config dataset for zones... " >>/dev/console
    zfs create ${CONFDS} || fatal "failed to create the config dataset"
    chmod 755 /${CONFDS}
    cp -p /etc/zones/* /${CONFDS}
    zfs set mountpoint=legacy ${CONFDS}
    echo "done." >>/dev/console

    if [[ -n $(/bin/bootparams | grep "^headnode=true") ]]; then
        echo -n "Creating usbkey dataset... " >>/dev/console
        zfs create -o mountpoint=legacy ${USBKEYDS} || \
          fatal "failed to create the usbkey dataset"
        echo "done." >>/dev/console
    fi

    echo -n "Creating opt dataset... " >>/dev/console
    zfs create -o mountpoint=legacy ${OPTDS} || \
      fatal "failed to create the opt dataset"
    echo "done." >>/dev/console

    echo -n "Initializing var dataset... " >/dev/console
    zfs create ${VARDS} || \
      fatal "failed to create the var dataset"
    chmod 755 /${VARDS}
    cd /var
    if ( ! find . -print | cpio -pdm /${VARDS} ); then
        fatal "failed to initialize the var directory"
    fi

    zfs set mountpoint=legacy ${VARDS}
    echo "done." >>/dev/console
}

create_swap()
{
    USB_PATH=/mnt/`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/joyent`
    USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/joyent`

    swapsize=2g

    if [ -n "${arg_swap}" ]; then
        swapsize=${arg_swap}
    elif [ -f "${USB_COPY}/config" ]; then
        swapsize=$(grep "^swap=" ${USB_COPY}/config | cut -d'=' -f2-)
    elif [ -f "${USB_PATH}/config" ]; then
        swapsize=$(grep "^swap=" ${USB_PATH}/config | cut -d'=' -f2-)
    fi

    echo -n "Creating swap zvol... " >>/dev/console
    zfs create -V ${swapsize} ${SWAPVOL}
    echo "done." >>/dev/console
}

POOLS=`zpool list`
if [[ ${POOLS} == "no pools available" ]]; then
    create_zpool
    setup_datasets
    create_swap
    if [[ -z $(/usr/bin/bootparams | grep "headnode=true") ]]; then
        # don't reboot if we're a headnode because headnode.sh wants to do more first.
        reboot
    fi
fi
