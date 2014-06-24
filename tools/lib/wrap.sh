#!/bin/bash

set -o errexit
set -o pipefail

#
# Call the tool of the same name in the 'sdc' zone.
#
# Note: That tool needs to be runnable from the GZ, i.e. calculates
# paths to files in the sdc zone *relative* to itself, etc.
#
ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
sdc_zone=$(vmadm list -H -o tags.smartdc_role,uuid,create_timestamp \
           -s create_timestamp owner_uuid=$ufds_admin_uuid | grep '^sdc\>' | \
           tail -1 | awk '{print $2}')
if [[ -z "${sdc_zone}" ]]; then
    # BASHSTYLED
    echo "error: $(basename $0): unable to find a 'sdc' core zone on this node" >&2
    exit 1
fi
exec /zones/$sdc_zone/root/opt/smartdc/sdc/bin/$(basename $0) "$@"
