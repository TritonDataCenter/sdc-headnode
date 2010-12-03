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

for zone in `ls /mnt/zones`; do
    if [[ ! `echo ${ZONES} | grep ${zone} ` ]]; then
        echo -n "creating zone ${zone}... " >>/dev/console
        dladm show-phys -m -p -o link,address | sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} vnic${NEXTVNIC}
                break
            fi
        done
        zonecfg -z ${zone} -f /mnt/zones/${zone}/config
        zonecfg -z ${zone} "add net; set physical=vnic${NEXTVNIC}; end"
        zoneadm -z ${zone} install -t ${LATESTTEMPLATE}
        #bzcat /mnt/zones/fs/${zone}.zfs.bz2 | zfs recv -e zones
        #zoneadm -z ${zone} attach
        (cd /zones/${zone}; bzcat /mnt/zones/${zone}/fs.tar.bz2 | tar -xf - )
        if [[ -f "/mnt/zones/${zone}/zoneconfig" ]]; then
            cp /mnt/zones/${zone}/zoneconfig /zones/${zone}/root/root/zoneconfig
        fi
        if [[ -f "/mnt/zones/${zone}/pkgsrc" ]]; then
            mkdir -p /zones/${zone}/root/root/pkgsrc
            cp /mnt/zones/${zone}/pkgsrc /zones/${zone}/root/root/pkgsrc/order
            for pkg in `cat /mnt/zones/${zone}/pkgsrc`; do
                cp /mnt/pkgsrc/${pkg}.tgz /zones/${zone}/root/root/pkgsrc
            done
            mkdir -p /zones/${zone}/root/root/zoneinit.d
            cp /mnt/zoneinit/94-zone-pkgs.sh /zones/${zone}/root/root/zoneinit.d
        fi
        if [[ -f "/mnt/zones/${zone}/zoneinit-finalize" ]]; then
            mkdir -p /zones/${zone}/root/root/zoneinit.d
            cp /mnt/zones/${zone}/zoneinit-finalize /zones/${zone}/root/root/zoneinit.d/99-${zone}-finalize.sh
        fi
        echo ${zone} > /zones/${zone}/root/etc/hostname.vnic${NEXTVNIC}
        cat /zones/${zone}/root/etc/motd | sed -e 's/ *$//' > /tmp/motd.new \
            && cp /tmp/motd.new /zones/${zone}/root/etc/motd \
            && rm /tmp/motd.new
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

# XXX Wait for zoneinit to finish, look at files instead?
echo -n "waiting for zoneinit... " >>/dev/console
sleep 10
echo "done." >>/dev/console

for zone in `ls /mnt/zones`; do

    # XXX Fix the .bashrc (See comments on https://hub.joyent.com/wiki/display/sys/SOP-097+Shell+Defaults)
    sed -e "s/PROMPT_COMMAND/[ -n \"\${SSH_CLIENT}\" ] \&\& PROMPT_COMMAND/" /zones/${zone}/root/root/.bashrc > /tmp/newbashrc \
    && cp /tmp/newbashrc /zones/${zone}/root/root/.bashrc

    echo -n "rebooting ${zone}... " >>/dev/console
    zlogin ${zone} reboot
    echo "done." >>/dev/console
done

# XXX HACK!
echo -n "Cleaning up... " >>/dev/console
sleep 5
for zone in `ls /mnt/zones`; do
    zlogin ${zone} svcadm clear network/physical:default
done
sleep 1
zlogin dhcpd svcadm clear dhcpd
echo "done." >> /dev/console

echo "==> Setup complete.  Press [enter] to get login prompt." >>/dev/console
echo "" >>/dev/console

exit 0
