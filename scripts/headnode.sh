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


# All the files come from USB, so we need that mounted.
if ! mount_usb; then
    # This is to move us to the next line past the login: prompt
    echo "" >>/dev/console
    echo "FATAL: Cannot find USB key... ${mount_usb_msg}" >>/dev/console
    exit 1;
fi

# Create a link to the config as /etc/headnode.config, so we can have a
# consistent location for it when we want to be able to umount the USB later
ln -s /mnt/config /etc/headnode.config

admin_nic=`/usr/bin/bootparams | grep "^admin_nic=" | cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`
default_gateway=`grep "^default_gateway=" /etc/headnode.config 2>/dev/null | cut -f2 -d'='`

# check if we've imported a zpool
POOLS=`zpool list`

if [[ ${POOLS} == "no pools available" ]]; then

    # This is to move us to the next line past the login: prompt
    echo "" >>/dev/console

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

USBZONES=`ls /mnt/zones`
ALLZONES=`for x in ${ZONES} ${USBZONES}; do echo ${x}; done | sort -r | uniq | xargs`
CREATEDZONES=

for zone in $ALLZONES; do
    if [[ ! `echo ${ZONES} | grep ${zone} ` ]]; then

        # This is to move us to the next line past the login: prompt
        [ -z ${CREATEDZONES} ] && echo "" >>/dev/console

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
        (cd /zones/${zone}; bzcat /mnt/zones/${zone}/fs.tar.bz2 | tar -xf - )
        chown root:sys /zones/${zone}
        chmod 0700 /zones/${zone}
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

	cat /zones/${zone}/root/root/zoneinit.d/93-pkgsrc.sh \
            | sed -e "s/^pkgin update/# pkgin update/" \
            > /zones/${zone}/root/root/zoneinit.d/93-pkgsrc.sh.new \
            && mv /zones/${zone}/root/root/zoneinit.d/93-pkgsrc.sh.new /zones/${zone}/root/root/zoneinit.d/93-pkgsrc.sh

        zoneip=`grep PRIVATE_IP /mnt/zones/${zone}/zoneconfig | cut -f 2 -d '='`
        echo ${zoneip} > /zones/${zone}/root/etc/hostname.vnic${NEXTVNIC}

        cat /zones/${zone}/root/etc/motd | sed -e 's/ *$//' > /tmp/motd.new \
            && cp /tmp/motd.new /zones/${zone}/root/etc/motd \
            && rm /tmp/motd.new

	# this allows a zone-specific motd message to be appended
	if [[ -f /mnt/zones/${zone}/motd.append ]]; then
            cat /mnt/zones/${zone}/motd.append >> /zones/${zone}/root/etc/motd
        fi

        if [[ -n ${default_gateway} ]]; then
            echo "${default_gateway}" > /zones/${zone}/root/etc/defaultrouter
        fi

        echo "done." >>/dev/console

        CREATEDZONES="${CREATEDZONES} ${zone}"
    else
        dladm show-phys -m -p -o link,address | sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} vnic${NEXTVNIC}
                break
            fi
        done
    fi
    NEXTVNIC=$((${NEXTVNIC} + 1))
done

# XXX why do we need this here, isn't something else supposed to boot autoboot zones?
# if so, this should be moved to only boot just-created zones.
for zone in ${ALLZONES}; do
    zoneadm -z ${zone} boot
done

# Add all "system"/USB zones to /etc/hosts in the GZ
for zone in rabbitmq mapi dhcpd; do
    zonename=$(grep "^ZONENAME=" /mnt/zones/${zone}/zoneconfig | cut -d'=' -f2-)
    hostname=$(grep "^HOSTNAME=" /mnt/zones/${zone}/zoneconfig | cut -d'=' -f2- | sed -e "s/\${ZONENAME}/${zonename}/")
    priv_ip=$(grep "^PRIVATE_IP=" /mnt/zones/${zone}/zoneconfig | cut -d'=' -f2-)
    if [[ -n ${zonename} ]] && [[ -n ${hostname} ]] && [[ -n ${priv_ip} ]]; then
        grep "^${priv_ip}	" /etc/hosts >/dev/null \
          || printf "${priv_ip}\t${zonename} ${hostname}\n" >> /etc/hosts
    fi
done

if [ -n "${CREATEDZONES}" ]; then
    for zone in ${CREATEDZONES}; do
        if [ -e /zones/${zone}/root/root/zoneinit ]; then
            echo -n "${zone}: waiting for zoneinit." >>/dev/console
            loops=0
            while [ -e /zones/${zone}/root/root/zoneinit ]; do
                sleep 2
                echo -n "." >> /dev/console
                loops=$((${loops} + 1))
                [ ${loops} -ge 59 ] && break
            done
            if [ ${loops} -ge 59 ]; then
                echo " timeout!" >>/dev/console
                ls -l /zones/${zone}/root/root >> /dev/console
            else
                echo " done." >>/dev/console
            fi
        fi

        # disable zoneinit now that we're done with it.
        zlogin ${zone} svcadm disable zoneinit >/dev/null 2>&1

        # XXX Fix the .bashrc (See comments on https://hub.joyent.com/wiki/display/sys/SOP-097+Shell+Defaults)
        sed -e "s/PROMPT_COMMAND/[ -n \"\${SSH_CLIENT}\" ] \&\& PROMPT_COMMAND/" /zones/${zone}/root/root/.bashrc > /tmp/newbashrc \
        && cp /tmp/newbashrc /zones/${zone}/root/root/.bashrc

        echo -n "rebooting ${zone}... " >>/dev/console
        zlogin ${zone} reboot
        echo "done." >>/dev/console
    done

    echo "==> Setup complete.  Press [enter] to get login prompt." >>/dev/console
    echo "" >>/dev/console
fi

exit 0
