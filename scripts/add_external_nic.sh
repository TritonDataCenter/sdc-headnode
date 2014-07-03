#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# add_external_nics.sh add an external nic to a zone.
#

# BASHSTYLED
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/opt/smartdc/bin:$PATH

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}

function add_external_nic {
    local zone_uuid=$1
    local external_net_uuid
    external_net_uuid=$(sdc-napi /networks?nic_tag=external | json -Ha uuid)
    local tmpfile=/tmp/update_nics.$$.json

    local num_nics
    num_nics=$(sdc-vmapi /vms/${zone_uuid} | json -H nics.length);

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

    rm -f ${tmpffile}
}

add_external_nic $1
