#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

#
# Call the tool of the same name in the 'sdc' zone.
#
# Note: That tool needs to be runnable from the GZ, i.e. calculates
# paths to files in the sdc zone *relative* to itself, etc.
#

if [[ -n "$TRACE" ]]; then
    # BASHSTYLED
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
sdc_zone=$(vmadm list -H -o tags.smartdc_role,uuid,create_timestamp \
           -s create_timestamp owner_uuid=$ufds_admin_uuid | \
           (grep '^sdc\>' || true) | \
           tail -1 | awk '{print $2}')
if [[ -z "${sdc_zone}" ]]; then
    # BASHSTYLED
    echo "error: $(basename $0): unable to find a 'sdc' core zone on this node" >&2
    exit 1
fi

if [[ ! -x /zones/${sdc_zone}/root/opt/smartdc/sdc/bin/$(basename $0) ]]; then
    echo "error: $(basename $0) executable not found in sdc zone" >&2
    exit 2
fi

exec /zones/$sdc_zone/root/opt/smartdc/sdc/bin/$(basename $0) "$@"
