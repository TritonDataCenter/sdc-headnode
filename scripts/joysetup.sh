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

    /usr/bin/bootparams | grep "headnode=true"
    if [[ $? -eq 0 ]]; then
        for disk in `/usr/bin/disklist -n`; do
            # Only include disks that aren't mounted (so we skip USB Key)
            grep ${disk} /etc/mnttab
            if [[ $? == 1 ]]; then
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

    [ $? -ne 0 ] && fatal "failed to create the zpool"
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
    zfs create -V ${base_size}mb ${ZPOOL}/dump
    [ $? -ne 0 ] && fatal "failed to create the dump zvol"
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
    zfs create ${CONFDS}
    [ $? -ne 0 ] && fatal "failed to create the config dataset"
    chmod 755 /${CONFDS}
    cp -p /etc/zones/* /${CONFDS}
    zfs set mountpoint=legacy ${CONFDS}
    echo "done." >>/dev/console

    echo -n "Creating usbkey dataset... " >>/dev/console
    zfs create -o mountpoint=legacy ${USBKEYDS}
    [ $? -ne 0 ] && fatal "failed to create the usbkey dataset"
    echo "done." >>/dev/console

    echo -n "Creating opt dataset... " >>/dev/console
    zfs create -o mountpoint=legacy ${OPTDS}
    [ $? -ne 0 ] && fatal "failed to create the opt dataset"
    echo "done." >>/dev/console

    echo -n "Initializing var dataset... " >/dev/console
    zfs create ${VARDS}
    [ $? -ne 0 ] && fatal "failed to create the var dataset"
    chmod 755 /${VARDS}
    cd /var
    find . -print | cpio -pdm /${VARDS}
    [ $? -ne 0 ] && fatal "failed to initialize the var directory"
    zfs set mountpoint=legacy ${VARDS}
    echo "done." >>/dev/console
}

create_swap()
{
    if [ -f "/etc/headnode.config" ]; then
        swapsize=$(grep "^swap=" /etc/headnode.config | cut -d'=' -f2-)
        if [[ -n ${swapsize} ]]; then
            echo -n "Creating swap zvol... " >>/dev/console
            zfs create -V ${swapsize} ${SWAPVOL}
            echo "done." >>/dev/console
        fi
    fi
}

POOLS=`zpool list`
if [[ ${POOLS} == "no pools available" ]]; then
    create_zpool
    setup_datasets
    create_swap
    /usr/bin/bootparams | grep "headnode=true"
    if [[ $? -ne 0 ]]; then
        # don't reboot if we're a headnode because headnode.sh wants to do more first.
        reboot
    fi
fi
