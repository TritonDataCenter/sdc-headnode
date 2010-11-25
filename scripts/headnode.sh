#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
#
# Exit codes:
#
# 0 - success
# 1 - error
# 2 - rebooting (don't bother doing anything)
#

DEBUG="true"

. /lib/svc/share/joyent_include.sh

# This is to move us to the next line past the login: prompt
echo "" >>/dev/console

# All the files come from USB, so we need that mounted.
if ! mount_usb; then
    echo "FATAL: Cannot find USB key... ${mount_usb_msg}" >>/dev/console
    exit 1;
fi

if [[ ${DEBUG} == "true" ]]; then
    echo "mount_usb() said... ${mount_usb_msg}" >>/dev/console
fi

admin_nic=`/usr/bin/bootparams | grep "^admin_nic=" | cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`

# check if we've imported a zpool
POOLS=`zpool list`

if [[ ${POOLS} == "no pools available" ]]; then
    /mnt/scripts/joysetup.sh || exit 1
    echo -n "Importing zone template dataset... " >>/dev/console
    bzcat /mnt/bare.zfs.bz2 | zfs recv -e zones || exit 1;
    echo "done." >>/dev/console
    reboot
    exit 2
fi

# Now the infrastructure zones

NEXTVNIC=`dladm show-vnic | grep -c vnic`

ZONES=`zoneadm list -i | grep -v "^global$"`

LATESTTEMPLATE=''
for template in `ls /zones | grep bare`; do
    LATESTTEMPLATE=${template}
done

for zone in `ls /mnt/zones/config`; do
    if [[ ! `echo ${ZONES} | grep ${zone} ` ]]; then
        echo -n "creating zone ${zone}... " >>/dev/console
        dladm show-phys -m -p -o link,address | sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} vnic${NEXTVNIC}
                break
            fi
        done
        zonecfg -z ${zone} -f /mnt/zones/config/${zone}
        zonecfg -z ${zone} "add net; set physical=vnic${NEXTVNIC}; end"
        zoneadm -z ${zone} install -t ${LATESTTEMPLATE}
        #bzcat /mnt/zones/fs/${zone}.zfs.bz2 | zfs recv -e zones
        #zoneadm -z ${zone} attach
        (cd /zones/${zone}; bzcat /mnt/zones/fs/${zone}.tar.bz2 | tar -xf - )
        echo ${zone} > /zones/${zone}/root/etc/hostname.vnic${NEXTVNIC}
        echo "done." >>/dev/console
    else
        dladm show-phys -m -p -o link,address | sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} vnic${NEXTVNIC}
                break
            fi
        done
    fi
    NEXTVNIC=$((${NEXTVNIC} + 1))
    zoneadm -z ${zone} boot
done

exit 0
