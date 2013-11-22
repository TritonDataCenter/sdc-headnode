#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# setup_manta_zone.sh: bootstrap a manta deployment zone
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/opt/smartdc/bin:$PATH

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

add_external_nic $1
