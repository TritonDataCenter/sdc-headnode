#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#
# Exit codes:
#
# 0 - success
# 1 - error
#

ERRORLOG="/tmp/create_zone-$1.$$"
exec 5>${ERRORLOG}
BASH_XTRACEFD=5
export PS4='+(${BASH_SOURCE}:${LINENO}): ${SECONDS} ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#
# We set errexit (a.k.a. "set -e") to force an exit on error conditions, and
# pipefail to force any failures in a pipeline to force overall failure.  We
# also set xtrace to aid in debugging.
#
set -o errexit
set -o pipefail
set -o xtrace

if [[ -z ${CONSOLE_FD} ]]; then
    CONSOLE_FD=2
fi

function fatal
{
    echo "create-zone.sh error: $*" >&${CONSOLE_FD}
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
                datacenter_name \
                root_authorized_keys_file \
                compute_node_initial_datasets \
                assets_admin_ip \
                atropos_admin_ip \
                compute_node_ntp_conf_file \
                compute_node_ntp_hosts \
                rabbitmq \
                root_shadow \
                capi_admin_ip \
                capi_client_url \
                capi_http_admin_user \
                capi_http_admin_pw \
                ; do

                value=$(eval echo \${${opt}})
                # strip off compute_node_ from beginning of those variables
                opt=${opt#compute_node_}
                if [[ -n ${value} ]]; then
                    echo "${opt}='${value}'"

                    if echo "${opt}" | grep "_file$" >/dev/null 2>&1 \
                        && [[ "${value}" != "node.config" ]]; then

                        [[ -f "${USB_COPY}/config.inc/${value}" ]] \
                            && cp "${USB_COPY}/config.inc/${value}" "${dir}/${value}"
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

function update_datasets
{
    option=$1

    # pull out those config options we want to keep
    assets_ip=$(
        . ${USB_COPY}/config
        eval echo "\${${option}}"
    )

    # Rewrite the new local dataset url
    # Hardcoded global assets url?
    for file in $(ls ${USB_COPY}/datasets/*.dsmanifest); do
        /usr/bin/sed -i "" -e "s|\"url\": \"https:.*/|\"url\": \"http://${assets_ip}/|" $file
    done
}

# main()

trap 'errexit $?' EXIT

USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/smartdc:default`

zone=$1
opt=$2
if [[ -z ${zone} || ! -d ${USB_COPY}/zones/${zone} || ! -z $3 ]] \
  || [[ -n ${opt} && ${opt} != "-w" ]]; then

    echo "Usage: $0 <zone> [-w]"
    exit 1
fi

wait_for_zoneinit="false"
if [[ ${opt} == "-w" ]]; then
    wait_for_zoneinit="true"
fi

# Load config variables with CONFIG_ prefix
. /lib/sdc/config.sh
load_sdc_config

LATESTTEMPLATE=''
for template in `ls /zones | grep smartos`; do
    LATESTTEMPLATE=${template}
done

src=${USB_COPY}/zones/${zone}

zone_external_ip=
zone_admin_ip=
zone_external_netmask=
zone_admin_netmask=

if [[ -f "${src}/zoneconfig" ]]; then
    # zoneconfig can use variables from usbkey/config, so we
    # need to pull these two values this way.
    zoneips=$(
        . ${USB_COPY}/config
        . ${src}/zoneconfig
        echo "${PRIVATE_IP},${PUBLIC_IP}"
    )
    zone_admin_ip=${zoneips%%,*}
    zone_external_ip=${zoneips##*,}

    zone_admin_netmask=${CONFIG_admin_netmask}
    zone_external_netmask=${CONFIG_external_netmask}
fi

zone_external_vlan=$(eval "echo \${CONFIG_${zone}_external_vlan}")
[[ -n ${zone_external_vlan} ]] || zone_external_vlan=0

zone_external_vlan_opts=
if [[ -n "${zone_external_vlan}" ]] && [[ "${zone_external_vlan}" != "0" ]]; then
    zone_external_vlan_opts="-v ${zone_external_vlan}"
fi

zone_dhcp_server_enable=""
zone_dhcp_server=$(eval "echo \${CONFIG_${zone}_dhcp_server}")
[[ -n ${zone_dhcp_server} ]] &&
    zone_dhcp_server_enable="add property (name=dhcp_server,value=1)"

echo -n "creating zone ${zone}... " >&${CONSOLE_FD}
zonecfg -z ${zone} -f ${src}/config

eval zone_cpu_shares=\${CONFIG_${zone}_cpu_shares}
eval zone_max_lwps=\${CONFIG_${zone}_max_lwps}
eval zone_memory_cap=\${CONFIG_${zone}_memory_cap}

if [[ -n "${zone_cpu_shares}" ]]; then
    zonecfg -z ${zone} "set cpu-shares=${zone_cpu_shares};"
fi
if [[ -n "${zone_max_lwps}" ]]; then
    zonecfg -z ${zone} "set max-lwps=${zone_max_lwps};"
fi
if [[ -n "${zone_memory_cap}" ]]; then
    zonecfg -z ${zone} "add capped-memory; set physical=${zone_memory_cap}; end"
fi

zonecfg -z ${zone} "add net; set physical=${zone}0; set vlan-id=0; set global-nic=admin; ${zone_dhcp_server_enable}; end; exit"
if [[ -n "${zone_external_ip}" ]] && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
   zonecfg -z ${zone} "add net; set physical=${zone}1; set vlan-id=${zone_external_vlan}; set global-nic=external; ${zone_dhcp_server_enable}; end; exit"
fi

zoneadm -z ${zone} install -t ${LATESTTEMPLATE}

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
        # Grab list of assets files actually in datasets repo
        assets_available_dataset_list=$(cd /${USB_COPY}/datasets \
            && ls *.zfs.bz2 | xargs | tr ' ' ',')

        . ${USB_COPY}/config
        . ${src}/zoneconfig

        for var in $(cat ${src}/zoneconfig | grep -v "^ *#" | grep "=" | cut -d'=' -f1); do
            echo "${var}='${!var}'"
        done
    ) > ${dest}/root/zoneconfig
    echo "DEBUG ${dest}/root/zoneconfig" >&5
    cat ${dest}/root/zoneconfig >&5

    # Save the zoneconfig file so the configure script can use it.
    mkdir -p ${dest}/opt/smartdc/etc
    cp ${dest}/root/zoneconfig ${dest}/opt/smartdc/etc/zoneconfig
fi

# Copy the configure and configure.sh scripts to the right place
if [[ -f "${src}/configure" ]]; then
    mkdir -p ${dest}/opt/smartdc/bin
    cp ${src}/configure ${dest}/opt/smartdc/bin/configure
    chmod 0755 ${dest}/opt/smartdc/bin/configure
fi
if [[ -f "${src}/configure.sh" ]]; then
    mkdir -p ${dest}/opt/smartdc/bin
    cp ${src}/configure.sh ${dest}/opt/smartdc/bin/configure.sh
    chmod 0644 ${dest}/opt/smartdc/bin/configure.sh
fi

# Ditto for backup/restore scripts
if [[ -f "${src}/backup" ]]; then
    mkdir -p ${dest}/opt/smartdc/bin
    cp ${src}/backup ${dest}/opt/smartdc/bin/backup
    chmod 0755 ${dest}/opt/smartdc/bin/backup
fi
if [[ -f "${src}/restore" ]]; then
    mkdir -p ${dest}/opt/smartdc/bin
    cp ${src}/restore ${dest}/opt/smartdc/bin/restore
    chmod 0755 ${dest}/opt/smartdc/bin/restore
fi

# Write the info about this datacenter to /.dcinfo so we can use it in
# the zone.  Same file should be put in the GZ by smartdc:config
cat >${dest}/.dcinfo <<EOF
SDC_DATACENTER_NAME="${CONFIG_datacenter_name}"
SDC_DATACENTER_HEADNODE_ID=${CONFIG_datacenter_headnode_id}
EOF

# Copy in special .bashrc for headnode zones.
[[ -f "${USB_COPY}/rc/zone.root.bashrc" ]] \
    && cp ${USB_COPY}/rc/zone.root.bashrc ${dest}/root/.bashrc

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
    echo "${zone_admin_ip} netmask ${zone_admin_netmask}" \
        > ${dest}/etc/hostname.${zone}0
fi
if [[ -n "${zone_external_ip}" ]] && [[ -n ${zone_external_netmask} ]] \
    && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then

    echo "${zone_external_ip} netmask ${zone_external_netmask}" \
        > ${dest}/etc/hostname.${zone}1
fi

# this allows a zone-specific motd message to be appended
if [[ -f ${dest}/etc/motd && -f ${src}/motd.append ]]; then
    cat ${src}/motd.append >> ${dest}/etc/motd
fi

# If there's a external IP set and headnode_default_gateway is set, use that.
# Otherwise, use admin_gateway if that's set.
if [[ -n "${zone_external_ip}" ]] \
  && [[ -n ${CONFIG_headnode_default_gateway} ]] \
  && [[ "${zone_external_ip}" != "${zone_admin_ip}" ]]; then
    echo "${CONFIG_headnode_default_gateway}" > ${dest}/etc/defaultrouter
elif [[ -n ${CONFIG_admin_gateway} ]]; then
    echo "${CONFIG_admin_gateway}" > ${dest}/etc/defaultrouter
fi

# Rewrite the new local dataset url
if [[ "${zone}" == "mapi" ]]; then
    update_datasets assets_admin_ip
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
if [[ -f ${dest}/root/root/zoneconfig ]]; then
    zonename=$(grep "^ZONENAME=" ${dest}/root/root/zoneconfig | cut -d"'" -f2)
    hostname=$(grep "^HOSTNAME=" ${dest}/root/root/zoneconfig | cut -d"'" -f2)
    priv_ip=$(grep "^PRIVATE_IP=" ${dest}/root/root/zoneconfig | cut -d"'" -f2)
    if [[ -n ${zonename} ]] && [[ -n ${hostname} ]] && [[ -n ${priv_ip} ]]; then
        grep "^${priv_ip}  " /etc/hosts >/dev/null \
          || printf "${priv_ip}\t${zonename} ${hostname}\n" >> /etc/hosts
    fi
fi

# Zero the zoneinit log, since we don't want logs coming from the datasets to
# confuse us.
find ${dest}/var/svc/log -type f -name "system-zoneinit*" -exec cp /dev/null {} \;

grep -v "/var/svc/log" ${dest}/root/zoneinit.d/11-files.delete \
    > ${dest}/root/zoneinit.d/11-files.delete.new \
    && mv ${dest}/root/zoneinit.d/11-files.delete.new \
       ${dest}/root/zoneinit.d/11-files.delete

zoneadm -z ${zone} boot
echo "done." >&${CONSOLE_FD}

if [[ ${wait_for_zoneinit} == "true" ]]; then
    if [ -e /zones/${zone}/root/root/zoneinit ]; then
        echo -n "${zone}: waiting for zoneinit." >&${CONSOLE_FD}
        loops=0
        while [ -e /zones/${zone}/root/root/zoneinit ]; do
            sleep 10
            echo -n "." >&${CONSOLE_FD}
            loops=$((${loops} + 1))
            [ ${loops} -ge 59 ] && break
        done
        if [ ${loops} -ge 59 ]; then
            echo " timeout!" >&${CONSOLE_FD}
            ls -l /zones/${zone}/root/root
        else
            echo " done." >&${CONSOLE_FD}
            # remove the pkgsrc dir now that zoneinit is done
            if [[ -d /zones/${zone}/root/pkgsrc ]]; then
                rm -rf /zones/${zone}/root/pkgsrc
            fi
        fi
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

    # Enable compression for the "ca" zone.
if [[ "${zone}" == "ca" ]]; then
    zfs set compression=lzjb zones/ca
fi

# Fix the .bashrc -- See comments on:
# https://hub.joyent.com/wiki/display/sys/SOP-097+Shell+Defaults
sed -e "s/PROMPT_COMMAND/[ -n \"\${SSH_CLIENT}\" ] \&\& PROMPT_COMMAND/" \
    /zones/${zone}/root/root/.bashrc > /tmp/newbashrc \
    && cp /tmp/newbashrc /zones/${zone}/root/root/.bashrc

exit 0
