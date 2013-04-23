#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# setup_manta_zone.sh: bootstrap a manta deployment zone
#

set -o xtrace

PATH=/opt/smartdc/bin:$PATH


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
                \"uuid\": \"${external_net_uuid}\"
            }
        ]
    }" > ${tmpfile}

    sdc-vmapi /vms/${zone_uuid}?action=add_nics -X POST \
        -d @${tmpfile}
    [[ $? -eq 0 ]] || fatal "failed to add external NIC"

    # The add_nics job takes 10-15 seconds.
    sleep 20

    vmadm reboot ${zone_uuid}
    [[ $? -eq 0 ]] || fatal "failed to reboot zone"

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
    local headnode_uuid=$(sysinfo | json UUID)
    sdc-role create ${headnode_uuid} manta
    [[ $? -eq 0 ]] || fatal "failed to provision manta zone"
}


# Mainline

manta_uuid=$(vmadm lookup alias=manta0)
if [[ -n ${manta_uuid} ]]; then
    echo "Manta zone already present."
    exit 0
fi

sapi_uuid=$(vmadm lookup alias=sapi0)

add_external_nic ${sapi_uuid}
import_manta_image
deploy_manta_zone
