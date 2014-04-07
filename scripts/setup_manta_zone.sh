#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# setup_manta_zone.sh: bootstrap a manta deployment zone
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/opt/smartdc/bin:$PATH

ZONE_ALIAS=manta0


function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}


function add_external_nic {
    local zone_uuid=$1
    local external_net_uuid=$(sdc-napi /networks?nic_tag=external |
        json -Ha uuid)
    local tmpfile=/tmp/update_nics.$$.json

    local num_nics=$(sdc-vmapi /vms/${zone_uuid} | json -H nics.length);
    if [[ ${num_nics} == 2 ]]; then
        return  # External NIC already present
    fi

    echo "Adding external NIC to ${zone_uuid}"

    echo "
    {
        \"networks\": [
            {
                \"uuid\": \"${external_net_uuid}\",
                \"primary\": true
            }
        ]
    }" > ${tmpfile}

    sdc-vmapi /vms/${zone_uuid}?action=add_nics -X POST \
        -d @${tmpfile}
    [[ $? -eq 0 ]] || fatal "failed to add external NIC"

    # The add_nics job takes about 20 seconds.
    sleep 30

    rm -f ${tmpffile}
}


function import_manta_image {
    local manifest=$(ls -r1 /usbkey/datasets/manta-d*imgmanifest | head -n 1)
    local file=$(ls -r1 /usbkey/datasets/manta-d*gz | head -n 1)
    local uuid=$(json -f ${manifest} uuid)

    echo $(basename ${manifest}) > /usbkey/zones/manta/dataset

    # If image already exists, don't import again.
    sdc-imgadm get ${uuid} >/dev/null
    if [[ $? -eq 0 ]]; then
        return
    fi

    sdc-imgadm import -m ${manifest} -f ${file}
    [[ $? -eq 0 ]] || fatal "failed to import image"
}


function deploy_manta_zone {
    local service_uuid=$(sdc-sapi /services?name=manta | json -Ha uuid)

    echo "
    {
        \"service_uuid\": \"${service_uuid}\",
        \"params\": {
            \"alias\": \"${ZONE_ALIAS}\"
        }
    }" | sapiadm provision

    [[ $? -eq 0 ]] || fatal "failed to provision manta zone"
}


function enable_firewall {
    local zone_uuid=$1
    vmadm update ${zone_uuid} firewall_enabled=true
    [[ $? -eq 0 ]] || fatal "failed to enable firewall for the manta zone"
}


# Wait for /opt/smartdc/manta-deployment/etc/config.json to be written out
# by config-agent.
function wait_for_config_agent {
    local CONFIG_PATH=/opt/smartdc/manta-deployment/etc/config.json
    local MANTA_ZONE=$(vmadm lookup -1 alias=${ZONE_ALIAS})
    echo "Wait up to a minute for config-agent to write '$CONFIG_PATH'."
    local ZONE_CONFIG_PATH=/zones/$MANTA_ZONE/root$CONFIG_PATH
    for i in {1..30}; do
        if [[ -f "$ZONE_CONFIG_PATH" ]]; then
            break
        fi
        sleep 2
    done
    if [[ ! -f "$ZONE_CONFIG_PATH" ]]; then
        fatal "Timeout waiting for '$ZONE_CONFIG_PATH' to be written."
    else
        echo "'$CONFIG_PATH' created in manta zone."
    fi
}


function wait_for_manta_zone {
    local zone_uuid=$1
    local state="unknown"
    for i in {1..60}; do
        state=$(vmadm lookup -j alias alias=${ZONE_ALIAS} | json -ga zone_state)
        if [[ "running" == "$state" ]]; then
            break
        fi
        sleep 1
    done
    if [[ "$state" != "running" ]]; then
        fatal "manta zone isn't running after reboot"
    else
        echo "manta zone running"
    fi
}


# Copy manta tools into the GZ from the manta zone
function copy_manta_tools {
    local zone_uuid=$1
    if [[ -n ${zone_uuid} ]]; then
        from_dir=/zones/${zone_uuid}/root/opt/smartdc/manta-deployment
        to_dir=/opt/smartdc/bin

        # remove any tools from a previous setup
        rm -f ${to_dir}/manta-status
        rm -f ${to_dir}/manta-login
        rm -f ${to_dir}/manta-adm

        mkdir -p /opt/smartdc/manta-deployment/log
        # manta-login is a bash script, so we can link it directly.
        ln -s ${from_dir}/bin/manta-login ${to_dir}/manta-login

        #
        # manta-status uses /usr/node/bin/node directly, so that just works too.
        # It's not valid to use that node here, but manta-status is deprecated
        # anyways.
        #
        ln -s ${from_dir}/cmd/manta-status.js ${to_dir}/manta-status

        #
        # manta-adm is a node program, so we must write a little wrapper that
        # calls the real version using the node delivered in the manta zone.
        #
        cat <<-EOF > ${to_dir}/manta-adm
	#!/bin/bash
	exec ${from_dir}/build/node/bin/node ${from_dir}/bin/manta-adm "\$@"
	EOF
        chmod +x ${to_dir}/manta-adm
    fi
}


# Mainline

manta_uuid=$(vmadm lookup -1 alias=${ZONE_ALIAS})
if [[ -n ${manta_uuid} ]]; then
    echo "Manta zone already present."
    exit 0
fi

imgapi_uuid=$(vmadm lookup alias=imgapi0)
add_external_nic ${imgapi_uuid}
enable_firewall ${imgapi_uuid}

import_manta_image
deploy_manta_zone
wait_for_config_agent
manta_zone_uuid=$(vmadm lookup -1 alias=${ZONE_ALIAS})
add_external_nic ${manta_zone_uuid}
wait_for_manta_zone ${manta_zone_uuid}
enable_firewall ${manta_zone_uuid}
copy_manta_tools ${manta_zone_uuid}
