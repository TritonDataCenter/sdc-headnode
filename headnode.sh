#!/usr/bin/bash
# Copyright (c) Joyent Inc

# First thing to do is to mount the USB key
USBKEYS=`/usr/bin/disklist -r`
for key in $USBKEYS; do
    if [[ `/usr/sbin/fstyp /dev/dsk/${key}p0:1` == 'pcfs' ]]; then
        /usr/sbin/mount -F pcfs /dev/dsk/${key}p0:1 /mnt;
        if [[ $? == 0 ]]; then
            if [[ ! -f /mnt/.joyliveusb ]]; then
                /usr/sbin/umount /mnt;
            else
                break;
            fi
        fi
    fi
done 

. /mnt/config

# check if we've imported a zpool
POOLS=`zpool list`

if [[ $POOLS == "no pools available" ]]; then
    /sbin/joysetup || exit 1
    echo "Importing zone template dataset" >/dev/console
    bzcat /mnt/bare.zfs.bz2 | zfs recv -e zones || exit 1;
    reboot
fi

# Now the infrastructure zones

NEXTVNIC=`dladm show-vnic | grep -c vnic` 

ZONES=`zoneadm list -i | grep -v global`

LATESTTEMPLATE=''
for template in `ls /zones | grep bare`; do
    LATESTTEMPLATE=$template
done

for zone in `ls /mnt/zones/config`; do
    if [[ ! `echo $ZONES | grep $zone ` ]]; then
        echo "creating zone $zone" >/dev/console
        dladm create-vnic -l $admin_nic vnic${NEXTVNIC}
        zonecfg -z ${zone} -f /mnt/zones/config/${zone}
        zonecfg -z ${zone} "add net; set physical=vnic${NEXTVNIC}; end"
        zoneadm -z ${zone} install -t $LATESTTEMPLATE
        #bzcat /mnt/zones/fs/${zone}.zfs.bz2 | zfs recv -e zones 
        #zoneadm -z ${zone} attach
        (cd /zones/${zone}; bzcat /mnt/zones/fs/${zone}.tar.bz2 | tar -xf - )
        echo $zone > /zones/${zone}/root/etc/hostname.vnic${NEXTVNIC}

    else
        dladm create-vnic -l $admin_nic vnic${NEXTVNIC};
    fi
    NEXTVNIC=$(($NEXTVNIC + 1))
    zoneadm -z ${zone} boot
done
