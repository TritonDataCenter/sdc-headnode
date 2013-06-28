#!/usr/bin/bash
#
# version-list.sh: list image uuids and corresponding git shas of
# deployed images.
#

# set -o errexit
# set -o xtrace

ROLES="adminui amon ca cnapi dapi dhcpd fwapi imgapi napi sapi usageapi vmapi workflow"

function print_version
{
    local JSON=$1
    local IMAGE_UUID=$(echo $JSON | json -a image_uuid)
    local ALIAS=$(echo $JSON | json -a alias)
    local VERSION=$(sdc-imgadm get $IMAGE_UUID | json version)
    # echo $IMAGE_UUID $VERSION $ROLE
    echo "export ${ROLE^^}_IMAGE=${IMAGE_UUID}"
}

for ROLE in $ROLES; do
    foo=$(vmadm lookup -j -o alias,uuid,image_uuid,tags tags.smartdc_role=$ROLE)
    print_version "$foo"
done
