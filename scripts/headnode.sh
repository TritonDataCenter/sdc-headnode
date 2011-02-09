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

function install_node_config
{
    dir=$1

    if [[ -n ${dir} ]] && [[ -d ${dir} ]]; then
        # pull out those config options we want to keep
        (
            . ${USB_COPY}/config

            # Options here should match key names from the headnode's config
            # that we want on compute nodes.
            for opt in \
                root_authorized_keys_file \
                ntp_conf_file \
                ntp_hosts \
                rabbitmq \
                root_shadow \
                ; do

                value=$(eval echo \${${opt}})
                if [[ -n ${value} ]]; then
                    echo "${opt}='${value}'"

                    if echo "${opt}" | grep "_file$" >/dev/null 2>&1 && [[ "${value}" != "node.config" ]]; then
                        [[ -f "${USB_COPY}/config.inc/${value}" ]] && cp "${USB_COPY}/config.inc/${value}" "${dir}/${value}"
                    fi
                fi

            done
        ) > ${dir}/node.config
    else
        echo "WARNING: Can't create node config in '${dir}'"
    fi
}

function install_config_file
{
    option=$1
    target=$2

    # pull out those config options we want to keep
    filename=$(
        . ${USB_COPY}/config
        eval echo "\${${option}}"
    )

    if [[ -n ${filename} ]] && [[ -f "${USB_COPY}/config.inc/${filename}" ]]; then
        cp "${USB_COPY}/config.inc/${filename}" "${target}"
    fi
}

trap 'errexit $?' EXIT

DEBUG="true"

USB_PATH=/mnt/`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/smartdc:default`
USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/smartdc:default`

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

    echo -n "Importing zone template datasets... " >>/dev/console
    templates=( bare-1.2.8 )
    for template in ${templates[@]}
    do
        bzcat ${USB_PATH}/datasets/${template}.zfs.bz2 | zfs recv -e zones || fatal "unable to import ${template}";
    done
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

# external_nic in boot params overrides config, but config is normal place for it
if ( /usr/bin/bootparams | grep "^external_nic=" 2> /dev/null ); then
    external_nic=`/usr/bin/bootparams | grep "^external_nic=" | \
      cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`
else
    external_nic=`grep "^external_nic=" /etc/headnode.config | \
      cut -f2 -d'=' | sed 's/0\([0-9a-f]\)/\1/g'`
fi

# Load headnode.config variables with CONFIG_ prefix, ignoring comments,
# spaces at the beginning of lines and lines that don't start with a letter.
eval $(cat /etc/headnode.config | sed -e "s/^ *//" | grep -v "^#" | grep "^[a-zA-Z]" | sed -e "s/^/CONFIG_/")

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

        src=${USB_COPY}/zones/${zone}

        zone_external_ip=
        zone_admin_ip=
        zone_external_netmask=
        zone_admin_netmask=

        if [[ -f "${src}/zoneconfig" ]]; then
            # We need to refigure this out each time because zoneconfig is gone on reboot
            zoneips=$(
                . ${USB_COPY}/config
                . ${src}/zoneconfig
                echo "${PRIVATE_IP},${PUBLIC_IP}"
            )
            zone_admin_ip=${zoneips%%,*}
            zone_external_ip=${zoneips##*,}

            zonemasks=$(
                . ${USB_COPY}/config
                echo "${admin_netmask},${external_netmask}"
            )
            zone_admin_netmask=${zonemasks%%,*}
            zone_external_netmask=${zonemasks##*,}
        fi

        zone_external_vlan=$(
            . ${USB_COPY}/config
            eval "echo \${${zone}_external_vlan}"
        )
        [[ -n ${zone_external_vlan} ]] || zone_external_vlan=0

        zone_external_vlan_opts=
        if [[ -n "${zone_external_vlan}" ]] && [[ "${zone_external_vlan}" != "0" ]]; then
            zone_external_vlan_opts="-v ${zone_external_vlan}"
        fi

        zfs_properties=""
        echo -n "creating zone ${zone}... " >>/dev/console
        zfs_properties=$(dladm show-phys -m -p -o link,address | \
          sed 's/:/\ /;s/\\//g' | while read iface mac; do
            if [[ ${mac} == ${admin_nic} ]]; then
                dladm create-vnic -l ${iface} ${zone}0
                admin_vnic_mac=$(dladm show-vnic -p -o MACADDRESS ${zone}0)

                # Add the zfs metadata so we know which network to attach this to on reboot
                echo -n "smartdc.network:${zone}0.vlan_id=0 "
                echo -n "smartdc.network:${zone}0.nic=admin "
                [[ -n ${admin_vnic_mac} ]] && echo -n "smartdc.network:${zone}0.mac=${admin_vnic_mac} "
            fi

            # if we have a PUBLIC_IP too, we need a second NIC
            if [[ ${mac} == ${external_nic} ]] && [[ -n "${zone_external_ip}" ]] && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
                dladm create-vnic -l ${iface} ${zone_external_vlan_opts} ${zone}1
                external_vnic_mac=$(dladm show-vnic -p -o MACADDRESS ${zone}1)

                # Add the zfs metadata so we know which network to attach this to on reboot
                echo -n "smartdc.network:${zone}1.vlan_id=${zone_external_vlan} "
                echo -n "smartdc.network:${zone}1.nic=external "
                [[ -n ${external_vnic_mac} ]] && echo -n "smartdc.network:${zone}1.mac=${external_vnic_mac} "
            fi
        done)

        zonecfg -z ${zone} -f ${src}/config

        # Set memory, cpu-shares and max-lwps which can be in config file
        # Do it in a subshell to avoid variable polution
       (
            . ${USB_COPY}/config
            eval zone_cpu_shares=\${${zone}_cpu_shares}
            eval zone_max_lwps=\${${zone}_max_lwps}
            eval zone_memory_cap=\${${zone}_memory_cap}

            if [[ -n "${zone_cpu_shares}" ]]; then
                zonecfg -z ${zone} "set cpu-shares=${zone_cpu_shares};"
            fi
            if [[ -n "${zone_max_lwps}" ]]; then
                zonecfg -z ${zone} "set max-lwps=${zone_max_lwps};"
            fi
            if [[ -n "${zone_memory_cap}" ]]; then
                zonecfg -z ${zone} "add capped-memory; set physical=${zone_memory_cap}; end"
            fi
        )

        zonecfg -z ${zone} "add net; set physical=${zone}0; end"
        if [[ -n "${zone_external_ip}" ]] && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
           zonecfg -z ${zone} "add net; set physical=${zone}1; end"
        fi
        zoneadm -z ${zone} install -t ${LATESTTEMPLATE}

        # At this point we have a zfs filesystem so we can apply our properties
        if [[ -n ${zfs_properties} ]]; then
            for prop in ${zfs_properties}; do
                zfs set "${prop}" zones/${zone}
            done
        fi

        (cd /zones/${zone}; bzcat ${src}/fs.tar.bz2 | tar -xf - )
        chown root:sys /zones/${zone}
        chmod 0700 /zones/${zone}

        dest=/zones/${zone}/root
        mkdir -p ${dest}/root/zoneinit.d

        if [[ -f "${src}/zoneconfig" ]]; then
            # This allows zoneconfig to use variables that exist in the <USB>/config file,
            # by putting them in the environment then putting the zoneconfig in the
            # environment, then printing all the variables from the file.  It is
            # done in a subshell to avoid further namespace polution.
            (
                . ${USB_COPY}/config
                . ${src}/zoneconfig
                for var in $(cat ${src}/zoneconfig | grep -v "^ *#" | grep "=" | cut -d'=' -f1); do
                    echo "${var}='${!var}'"
                done
            ) > ${dest}/root/zoneconfig
            echo "DEBUG ${dest}/root/zoneconfig"
            cat ${dest}/root/zoneconfig
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

        if [[ -n "${zone_admin_ip}" ]] && [[ -n ${zone_admin_netmask} ]]; then
            echo "${zone_admin_ip} netmask ${zone_admin_netmask}" > ${dest}/etc/hostname.${zone}0
        fi
        if [[ -n "${zone_external_ip}" ]] && [[ -n ${zone_external_netmask} ]] && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
            echo "${zone_external_ip} netmask ${zone_external_netmask}" > ${dest}/etc/hostname.${zone}1
        fi

        cat ${dest}/etc/motd | sed -e 's/ *$//' > /tmp/motd.new \
            && cp /tmp/motd.new ${dest}/etc/motd && rm /tmp/motd.new

        # this allows a zone-specific motd message to be appended
        if [[ -f ${src}/motd.append ]]; then
            cat ${src}/motd.append >> ${dest}/etc/motd
        fi

        # If there's a external IP set and an external_gateway, use that, otherwise use
        # admin_gateway if that's set.
        if [[ -n "${zone_external_ip}" ]] \
          && [[ -n ${CONFIG_external_gateway} ]] \
          && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
            echo "${CONFIG_external_gateway}" > ${dest}/etc/defaultrouter
        elif [[ -n ${CONFIG_admin_gateway} ]]; then
            echo "${CONFIG_admin_gateway}" > ${dest}/etc/defaultrouter
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

        # Add all "system"/USB zones to /etc/hosts in the GZ
        for z in rabbitmq mapi dhcpd adminui ca capi atropos pubapi; do
            if [[ "${z}" == "${zone}" ]]; then
                dest=/zones/${zone}/root
                zonename=$(grep "^ZONENAME=" ${dest}/root/zoneconfig | cut -d"'" -f2)
                hostname=$(grep "^HOSTNAME=" ${dest}/root/zoneconfig | cut -d"'" -f2)
                priv_ip=$(grep "^PRIVATE_IP=" ${dest}/root/zoneconfig | cut -d"'" -f2)
                if [[ -n ${zonename} ]] && [[ -n ${hostname} ]] && [[ -n ${priv_ip} ]]; then
                    grep "^${priv_ip}  " /etc/hosts >/dev/null \
                      || printf "${priv_ip}\t${zonename} ${hostname}\n" >> /etc/hosts
                fi
            fi
        done

        zoneadm -z ${zone} boot

        echo "done." >>/dev/console

        CREATEDZONES="${CREATEDZONES} ${zone}"
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

        # Install compute node config if we're MAPI
        if [[ "${zone}" == "mapi" ]]; then
            mkdir -p /zones/mapi/root/opt/smartdc/node.config
            install_node_config /zones/mapi/root/opt/smartdc/node.config
        fi

        # Install capi.allow if we've got one
        if [[ "${zone}" == "capi" ]]; then
            mkdir -p /zones/capi/root/opt/smartdc
            install_config_file capi_allow_file /zones/capi/root/opt/smartdc/capi.allow
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

    # We do this here because agents assume rabbitmq is up and by this point it
    # should be.
    if [[ ! -e "/opt/smartdc/agents/bin/atropos-agent" ]]; then
        echo -n "Installing agents... " >>/dev/console
        (cd /var/tmp ; bash ${USB_PATH}/ur-scripts/agents-*.sh)
        echo "done." >>/dev/console
    fi

    echo "==> Setup complete.  Press [enter] to get login prompt." >>/dev/console
    echo "" >>/dev/console
fi

exit 0
