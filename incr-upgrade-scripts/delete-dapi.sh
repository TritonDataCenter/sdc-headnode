#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Script to remove "dapi" zone, image and service in existing SDC 7 setups.
#
#     ./delete-dapi.sh
#
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit

UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
DAPI=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=dapi0)

# check that we can support DAPI's removal
sdc-cnapi --no-headers /allocate -X POST | json message | grep -q 'validation'

# remove amon probes for the zone
PROBES=$(sdc-amon /pub/admin/probes | json -Hc "this.agent === '$DAPI'" -a uuid)
for uuid in $PROBES; do
    sdc-amon /pub/admin/probes/$uuid -X DELETE
done

# remove dapi image(s)
sdc-imgadm list name=dapi -H -o uuid | xargs -n1 sdc-imgadm delete

# remove instance
sdc-sapi /instances/$DAPI -X DELETE

# remove service from SAPI
SAPI=$(sdc-sapi /services?name=dapi | json -Ha uuid)
sdc-sapi /services/$SAPI -X DELETE
