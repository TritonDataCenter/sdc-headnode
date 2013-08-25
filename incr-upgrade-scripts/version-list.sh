#!/usr/bin/bash
#
# version-list.sh: list image uuids and corresponding git shas of
# deployed images.
#
# Limitations:
# - This process can't handle multiple instances (e.g. two morays on beta-4)
# - Presumes all core zones are on the HN.
#

#set -o xtrace
set -o errexit
set -o pipefail


# This lists all SDC app services. However, not sure if some are not appropriate
# for rollback.
# - Skip 'moray' for now. 2 instances mucks this script up.
# - Skip 'manatee' because Matt says so, for now.
sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
ROLES=$(sdc-sapi /services?application_uuid=$sdc_app \
    | json -H -a name \
    | grep -v '^manatee$' \
    | grep -v '^moray$' \
    | sort | xargs)

function print_version
{
    local JSON=$1
    local IMAGE_UUID=$(echo $JSON | json -a image_uuid)
    [[ -z "$IMAGE_UUID" ]] && return
    local VERSION=$(sdc-imgadm get $IMAGE_UUID | json version)
    # echo $IMAGE_UUID $VERSION $ROLE
    echo "export ${ROLE^^}_IMAGE=${IMAGE_UUID}"
}

#echo "# ROLES: $ROLES"
for ROLE in $ROLES; do
    foo=$(vmadm lookup -j -o alias,uuid,image_uuid,tags tags.smartdc_role=$ROLE)
    print_version "$foo"
done
