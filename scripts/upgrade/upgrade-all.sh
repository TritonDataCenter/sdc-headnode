#!/usr/bin/bash
#
# upgrade-all.sh: upgrade SDC zones to latest images
#

set -o errexit
set -o xtrace

PATH=/opt/smartdc/bin:$PATH

UPDATES_IMGADM='/usr/node/bin/node /opt/smartdc/imgapi-cli/bin/updates-imgadm'

DC_NAME=$(sysinfo | json "Datacenter Name")

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}


function get_latest_image {
    local image_name=$1
    export image=$($UPDATES_IMGADM list name=${image_name} version=~master \
        | tail -1 | awk '{print $1}') || fatal "failed to get latest image"
}

function get_instance_uuid {
    local alias=$1
    export uuid=$(sdc-vmapi /vms?alias=${alias} | json -Ha uuid | head -n 1) || \
        fatal "failed to get instance UUID"
}

function upgrade_zone {
    local alias=$1
    local image_uuid=$2

    get_instance_uuid ${alias}
    local instance_uuid=${uuid}

    if [[ -z ${instance_uuid} ]]; then
        echo "No zone with alias ${alias}"
        return 0
    fi

    local current=$(vmadm get ${instance_uuid} | json -H image_uuid)

    if [[ ${current} == ${image_uuid} ]]; then
        printf "Instance %s already using image %s." \
            ${instance_uuid} ${image_uuid}
        return 0
    fi

    ./download-image.sh ${image_uuid} || fatal "failed to download image"

    set +o errexit
    imgadm get ${image_uuid} >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        imgadm import ${image_uuid} || fatal "failed to install image"
    fi
    set -o errexit

    if [[ ${DC_NAME} == "eu-ams-1" ]]; then
        vmadm stop ${instance_uuid}

        zfs unmount zones/cores/${instance_uuid}
        zfs unmount -f zones/${instance_uuid}

        # Both datasets should be unmounted

        zfs mount zones/${instance_uuid}
        zfs mount zones/cores/${instance_uuid}
    fi

    echo '{}' | json -e "this.image_uuid = '${image_uuid}'" |
        vmadm reprovision ${instance_uuid}

    printf "Instance %s reprovisioned with image %s\n" \
        ${instance_uuid} ${image_uuid}

    sleep 30  # To allow zone to start back up

    return 0
}

source ./images.sh

env | grep IMAGE

# XXX Don't upgrade the following zones: binder, manatee, manta, moray, and
# ufds.  Binder, manatee and moray will not work, manta is unnecessary, and
# don't do UFDS to minimize customer impact.
#
# XXX I hear from John he doesn't want us to upgrade keyapi/sdcsso this time.
#
# XXX Marsell points out it's pointless to upgrade rabbitmq.
#
# SAPI is upgraded separately through upgrade-sapi.sh.

upgrade_zone adminui0 $ADMINUI_IMAGE
upgrade_zone amon0 $AMON_IMAGE
upgrade_zone ca0 $CA_IMAGE
upgrade_zone cloudapi0 $CLOUDAPI_IMAGE
upgrade_zone cnapi0 $CNAPI_IMAGE
upgrade_zone dapi0 $DAPI_IMAGE
upgrade_zone dhcpd0 $DHCPD_IMAGE
upgrade_zone fwapi0 $FWAPI_IMAGE
upgrade_zone imgapi0 $IMGAPI_IMAGE
upgrade_zone napi0 $NAPI_IMAGE
upgrade_zone redis0 $REDIS_IMAGE
upgrade_zone usageapi0 $USAGEAPI_IMAGE
upgrade_zone vmapi0 $VMAPI_IMAGE
upgrade_zone workflow0 $WORKFLOW_IMAGE

exit 0
