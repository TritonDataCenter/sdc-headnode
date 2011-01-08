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

#
# We set errexit (a.k.a. "set -e") to force an exit on error conditions, and
# pipefail to force any failures in a pipeline to force overall failure.  We
# also set xtrace to aid in debugging.
#
set -o errexit
set -o pipefail
set -o xtrace

function fatal
{
    echo "head-node configuration: fatal error: $*" >> /dev/console
    echo "head-node configuration: fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0
    fatal "error exit status $1"
}

trap 'errexit $?' EXIT

DEBUG="true"

USB_PATH=`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/joyent`
USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/joyent`

# All the files come from USB, so we need that mounted.

# Create a link to the config as /etc/headnode.config, so we can have a
# consistent location for it when we want to be able to umount the USB later
ln -s ${USB_COPY}/config /etc/headnode.config

# check if we've imported a zpool
POOLS=`zpool list`

if [[ ${POOLS} == "no pools available" ]]; then

    # This is to move us to the next line past the login: prompt
    echo "" >>/dev/console

    ${USB_PATH}/scripts/joysetup.sh || exit 1

    echo -n "Importing zone template dataset... " >>/dev/console
    bzcat ${USB_PATH}/bare.zfs.bz2 | zfs recv -e zones || exit 1;
    echo "done." >>/dev/console
    reboot
    exit 2
fi

# admin_nic in boot params overrides config, but config is normal place for it
if ( /usr/bin/bootparams | grep "^admin_nic=" 2> /dev/null ); then
    admin_nic=`/usr/bin/bootparams | grep "^admin_nic=" | \
      cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`
else
    admin_nic=`grep "^admin_nic=" /etc/headnode.config | \
      cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`
fi

if ( grep "^default_gateway=" /etc/headnode.config ); then
    default_gateway=`grep "^default_gateway=" /etc/headnode.config \
      2>/dev/null | cut -f2 -d'='`
fi

# Now the infrastructure zones

if ( zoneadm list -i | grep -v "^global$" ); then
    ZONES=`zoneadm list -i | grep -v "^global$"`
else
    ZONES=
fi

LATESTTEMPLATE=''
for template in `ls /zones | grep bare`; do
    LATESTTEMPLATE=${template}
done

USBZONES=`ls ${USB_COPY}/zones`
ALLZONES=`for x in ${ZONES} ${USBZONES}; do echo ${x}; done | sort -r | uniq | xargs`
CREATEDZONES=

for zone in $ALLZONES; do
    if [[ -z $(echo "${ZONES}" | grep ${zone}) ]]; then

        # This is to move us to the next line past the login: prompt
        [[ -z "${CREATEDZONES}" ]] && echo "" >>/dev/console

        echo -n "creating zone ${zone}... " >>/dev/console
        dladm show-phys -m -p -o link,address | \
          sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} ${zone}0
                break
            fi
        done

        src=${USB_COPY}/zones/${zone}
        zonecfg -z ${zone} -f ${src}/config
        zonecfg -z ${zone} "add net; set physical=${zone}0; end"
        zoneadm -z ${zone} install -t ${LATESTTEMPLATE}
        (cd /zones/${zone}; bzcat ${src}/fs.tar.bz2 | tar -xf - )
        chown root:sys /zones/${zone}
        chmod 0700 /zones/${zone}

        dest=/zones/${zone}/root
        mkdir -p ${dest}/root/zoneinit.d

        if [[ -f "${src}/zoneconfig" ]]; then
            cp ${src}/zoneconfig ${dest}/root/zoneconfig
        fi

        if [[ -f "${src}/pkgsrc" ]]; then
            mkdir -p ${dest}/root/pkgsrc
            cp ${src}/pkgsrc ${dest}/root/pkgsrc/order
            (cd ${dest}/root/pkgsrc && tar -xf ${USB_COPY}/data/pkgsrc.tar \
              $(cat ${src}/pkgsrc | sed -e "s/$/.tgz/" | xargs))
            cp ${USB_COPY}/zoneinit/94-zone-pkgs.sh ${dest}/root/zoneinit.d
        fi

        if [[ -f "${src}/zoneinit-finalize" ]]; then
            cp ${USB_COPY}/zoneinit/zoneinit-common.sh \
              ${dest}/root/zoneinit.d/97-zoneinit-common.sh

            cp ${src}/zoneinit-finalize \
              ${dest}/root/zoneinit.d/99-${zone}-finalize.sh
        fi

        cat ${dest}/root/zoneinit.d/93-pkgsrc.sh \
            | sed -e "s/^pkgin update/# pkgin update/" \
            > ${dest}/root/zoneinit.d/93-pkgsrc.sh.new \
            && mv ${dest}/root/zoneinit.d/93-pkgsrc.sh.new \
            ${dest}/root/zoneinit.d/93-pkgsrc.sh

        zoneip=`grep PRIVATE_IP ${src}/zoneconfig | cut -f 2 -d '='`
        echo ${zoneip} > ${dest}/etc/hostname.${zone}0

        cat ${dest}/etc/motd | sed -e 's/ *$//' > /tmp/motd.new \
            && cp /tmp/motd.new ${dest}/etc/motd && rm /tmp/motd.new

        # this allows a zone-specific motd message to be appended
        if [[ -f ${src}/motd.append ]]; then
            cat ${src}/motd.append >> ${dest}/etc/motd
        fi

        if [[ -n ${default_gateway} ]]; then
            echo "${default_gateway}" > ${dest}/etc/defaultrouter
        fi

        # Create additional zone datasets when required:
        if [[ -f "${src}/zone-datasets" ]]; then
            source "${src}/zone-datasets"
        fi

        # Configure the extra zone datasets post zone boot, when given:
        if [[ -f "${src}/95-zone-datasets.sh" ]]; then
            cp "${src}/95-zone-datasets.sh" \
              ${dest}/root/zoneinit.d/95-zone-datasets.sh
        fi

        zoneadm -z ${zone} boot

        echo "done." >>/dev/console

        CREATEDZONES="${CREATEDZONES} ${zone}"
    fi
done

# Add all "system"/USB zones to /etc/hosts in the GZ
for zone in rabbitmq mapi dhcpd adminui ca capi atropos pubapi; do
    zonename=$(grep "^ZONENAME=" ${USB_COPY}/zones/${zone}/zoneconfig | cut -d'=' -f2-)
    hostname=$(grep "^HOSTNAME=" ${USB_COPY}/zones/${zone}/zoneconfig | cut -d'=' -f2- | sed -e "s/\${ZONENAME}/${zonename}/")
    priv_ip=$(grep "^PRIVATE_IP=" ${USB_COPY}/zones/${zone}/zoneconfig | cut -d'=' -f2-)
    if [[ -n ${zonename} ]] && [[ -n ${hostname} ]] && [[ -n ${priv_ip} ]]; then
        grep "^${priv_ip}  " /etc/hosts >/dev/null \
          || printf "${priv_ip}\t${zonename} ${hostname}\n" >> /etc/hosts
    fi
done

if [ -n "${CREATEDZONES}" ]; then
    for zone in ${CREATEDZONES}; do
        if [ -e /zones/${zone}/root/root/zoneinit ]; then
            echo -n "${zone}: waiting for zoneinit." >>/dev/console
            loops=0
            while [ -e /zones/${zone}/root/root/zoneinit ]; do
                sleep 10
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

        # copy headnode info into zone if we're MAPI
        if [[ "${zone}" == "mapi" ]] && [[ -d "/zones/mapi/root/opt/smartdc/mapi-data" ]]; then
            sysinfo > /zones/mapi/root/opt/smartdc/mapi-data/headnode-sysinfo.json
        fi

        # copy dhcpd configuration into zone if we're DHCPD
        if [[ "${zone}" == "dhcpd" ]] && [[ -d "/zones/dhcpd/root/etc" ]]; then
            ${USB_PATH}/zones/dhcpd/tools/dhcpconfig
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
