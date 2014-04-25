#!/usr/bin/bash
#
# get-changes.sh: gets changes between deployed and upgrade versions of
# a service.

# set -o errexit
# set -o xtrace

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}


if [[ -z $1 ]]; then
    fatal "Usage: get-changes.sh imagefile.sh"
fi
IMAGE_LIST=$1
source ${IMAGE_LIST}

ROLES="cnapi vmapi workflow"

function get_git_sha
{
    local VERSION=$1
}

function get_upgrade_image
{
    # use updates-imgadm
    local ROLE=$1
    local VAR=${ROLE^^}_IMAGE
    local UUID=${!VAR}
    echo $(updates-imgadm get $UUID | json -a version)
}

function get_current_image
{
    local ROLE=$1
    local UUID=$(vmadm lookup -j -o image_uuid,tags tags.smartdc_role=$ROLE | json -a image_uuid)
    echo $(sdc-imgadm get $UUID | json -a version | tail -1)
}

function print_diff
{
    local ROLE=$1
    local CURRENT=$(get_current_image $ROLE)
    CURRENT=$(expr match "$CURRENT" '.*\(-g[0-9a-f]*\)')
    local UPGRADE=$(get_upgrade_image $ROLE)
    UPGRADE=$(expr match "$UPGRADE" '.*\(-g[0-9a-f]*\)')
    echo "echo \"## $ROLE\" >> /tmp/upgrade.md"
    echo "echo ' ' >> /tmp/upgrade.md"
    echo "cd $ROLE"
    echo "git pull"
    echo "git log --oneline ${CURRENT:2}..${UPGRADE:2} >> /tmp/upgrade.md"
    echo "cd .."
    echo "echo ' ' >> /tmp/upgrade.md"
    echo "echo ' ' >> /tmp/upgrade.md"
}

echo "touch /tmp/upgrade.md"
echo "echo \"# UPGRADE CHANGES\" >> /tmp/upgrade.md"
echo "echo ' ' >> /tmp/upgrade.md"
for ROLE in $ROLES; do
    print_diff $ROLE
done
