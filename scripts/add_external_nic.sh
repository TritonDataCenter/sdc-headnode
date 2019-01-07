#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2019, Joyent, Inc.
#

#
# add_external_nics.sh add an external nic to a zone.
#

[[ -z "$1" ]] && echo "Usage: $(basename $0) <VM UUID>" && exit 1

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
    local tmpfile=/tmp/update_nics.$$.json

    echo "Adding external NIC to ${zone_uuid}"
    sdc-vmapi /vms/${zone_uuid}?action=add_nics -X POST --data-binary @- <<EOF
{
  "networks": [
    { "name": "external", "primary": true }
  ]
}
EOF
    [[ $? -eq 0 ]] || fatal "failed to add external NIC"
}

add_external_nic $1
