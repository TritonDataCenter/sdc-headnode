#!/bin/bash

PATH=/usr/bin:/usr/sbin
export PATH

ZPOOL=zones

CONFDS=$ZPOOL/config
OPTDS=$ZPOOL/opt
VARDS=$ZPOOL/var

fatal()
{
	echo "Error: $1" > /dev/console
	exit 1
}

#
# find disk(s) - either 1 disk or multiple - maybe raidz?
#
create_zpool()
{
	disks=`/usr/bin/disklist -n`

	# XXX what if no disks found?

	# XXX if more than one disk, create a raidz zpool
	# zpool create $ZPOOL raidz $disks

	# create a zpool with a single disk
	zpool create $ZPOOL $disks

	[ $? != 0 ] && fatal "creating the zpool"
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
	[ $base_size -gt 4096 ] && base_size=4096

	# Create the dump zvol
	zfs create -V ${base_size}mb $ZPOOL/dump
	[ $? != 0 ] && fatal "creating the dump zvol"
}

#
# Setup the persistent datasets on the zpool.
#
setup_datasets()
{
	echo "Making dump zvol">/dev/console
	create_dump

	echo "Initializing config dataset for zones." >/dev/console
	zfs create $CONFDS
	[ $? != 0 ] && fatal "creating the config dataset"
	chmod 755 /$CONFDS
	cp -p /etc/zones/* /$CONFDS
	zfs set mountpoint=legacy $CONFDS

	echo "Creating opt dataset" >/dev/console
	zfs create -o mountpoint=legacy $OPTDS
	[ $? != 0 ] && fatal "creating the opt dataset"

	echo "Initializing var dataset." >/dev/console
	zfs create $VARDS
	[ $? != 0 ] && fatal "creating the var dataset"
	chmod 755 /$VARDS
	cd /var
	find . -print | cpio -pdm /$VARDS
	[ $? != 0 ] && fatal "initializing the var directory"
	zfs set mountpoint=legacy $VARDS
	 
}

POOLS=`zpool list`
if [[ $POOLS == "no pools available" ]]; then
    create_zpool
    setup_datasets
fi