#!/usr/bin/bash
#
# Upgrade given SDC zones to latest images
#
# Usage:
#   ./upgrade-all.sh <upgrade-images-file>
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
    export uuid=$(sdc-vmapi /vms?alias=${alias}\&state=active | json -Ha uuid | head -n 1) || \
        fatal "failed to get instance UUID"
}

# XXX - for non-headnode upgrades, break this out.
function upgrade_zone {
    local alias=$1
    local image_uuid=$2

    get_instance_uuid ${alias}
    local instance_uuid=${uuid}

    if [[ -z ${instance_uuid} ]]; then
        echo "No zone with alias ${alias}"
        return 0
    fi

    local current_image_uuid=$(vmadm get ${instance_uuid} | json -H image_uuid)

    if [[ ${current_image_uuid} == ${image_uuid} ]]; then
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

    # XXX work around OS-2275
    local quota=$(vmadm get ${instance_uuid} | json quota)
    if [[ ${quota} == 0 ]]; then
        printf "Adding default quota of 25GiB for instance %s." \
            ${instance_uuid}
        vmadm update ${instance_uuid} quota=25
    fi

    if [[ ${DC_NAME} == "eu-ams-1" ]]; then
        vmadm stop ${instance_uuid}

        zfs unmount zones/cores/${instance_uuid}
        zfs unmount -f zones/${instance_uuid}

        # Both datasets should be unmounted

        zfs mount zones/${instance_uuid}
        zfs mount zones/cores/${instance_uuid}
    fi

    # if we have a user-script for this zone/image here we must be doing a
    # rollback so we want to use that user-script. If we don't have one, we
    # save the current one for future rollback.
    mkdir -p user-scripts
    if [[ -f user-scripts/${alias}.${image_uuid}.user-script ]]; then
        NEW_USER_SCRIPT=user-scripts/${alias}.${image_uuid}.user-script
    else
        vmadm get ${uuid} | json customer_metadata."user-script" \
            > user-scripts/${alias}.${current_image_uuid}.user-script
        [[ -s user-scripts/${alias}.${current_image_uuid}.user-script ]] \
            || fatal "Failed to create ${alias}.${current_image_uuid}.user-script"

        if [[ -f /usbkey/default/user-script.common ]]; then
            NEW_USER_SCRIPT=/usbkey/default/user-script.common
        else
            fatal "Unable to find user-script for ${alias}"
        fi
    fi
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} | vmadm update ${uuid}
    # also update SAPI's idea of what the user-script should be for future
    # provisions.
    mkdir -p sapi-updates
    service_uuid=$(sdc-sapi /instances/${uuid} | json -H service_uuid)
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} \
        | json -e "this.payload={metadata: this.set_customer_metadata}" payload \
        > sapi-updates/${service_uuid}.update
    sdc-sapi /services/${service_uuid} -X PUT -d @sapi-updates/${service_uuid}.update

    echo '{}' | json -e "this.image_uuid = '${image_uuid}'" |
        vmadm reprovision ${instance_uuid}

    printf "Instance %s reprovisioned with image %s\n" \
        ${instance_uuid} ${image_uuid}

    sleep 60  # To allow zone to start back up

    return 0
}

# posts a new manifest
function upgrade_manifests
{
    local alias=$1
    local manifest=$2

    get_instance_uuid ${alias}
    local instance_uuid=${uuid}

    local manifest_name=$(json -f ${manifest} name)

    if [[ -z ${instance_uuid} ]]; then
        echo "No zone with alias ${alias}"
        return 0
    fi

    # get service uuid.
    local service_uuid=$(sapiadm get ${instance_uuid} \
                         | json -H service_uuid)
    local service_name=$(sapiadm get ${service_uuid} \
                         | json -H name)
    # POST new manifest
    local manifest_uuid=$(sdc-sapi /manifests -X POST -d @${manifest} \
                          | json -H uuid)

    # PUT to service
    local update=$(echo '{ "manifests" : {} }' \
        | json -e "this.manifests.${manifest_name}=\"${manifest_uuid}\"")
    sdc-sapi /services/${service_uuid} -X PUT -d "${update}"

    printf "Service %s manifest %s updated." \
        ${service_name} ${manifest_name}
}


#---- mainline

IMAGE_LIST=$1
if [[ -z $1 ]]; then
    echo "Usage: upgrade-all.sh <update-images-file>"
    echo ""
    fatal "$0: error: no '<update-images-file>' given"
fi
[[ -f $IMAGE_LIST ]] || fatal "'$IMAGE_LIST' does not exist"
source $IMAGE_LIST
env | grep IMAGE

# XXX Don't upgrade the following zones: binder, manatee, manta, moray, and
# ufds.  Binder, manatee and moray will not work, manta is unnecessary, and
# don't do UFDS to minimize customer impact.
#
# XXX Marsell says it's pointless to upgrade rabbitmq.
#
# XXX JoshW says it's pointless to upgrade redis
# XXX Trent presumes it is currently pointless to upgrade amonredis
#
# XXX - workflow should probably go before CNAPI in general, as CNAPI fires
# off a number of sysinfo jobs.
# SAPI is upgraded separately through upgrade-sapi.sh.

[[ -n "$SDC_IMAGE" ]] && upgrade_zone sdc0 $SDC_IMAGE
[[ -n "$ADMINUI_IMAGE" ]] && upgrade_zone adminui0 $ADMINUI_IMAGE
[[ -n "$AMON_IMAGE" ]] && upgrade_zone amon0 $AMON_IMAGE
[[ -n "$AMONREDIS_IMAGE" ]] && upgrade_zone amonredis0 $AMONREDIS_IMAGE
[[ -n "$SDCSSO_IMAGE" ]] && upgrade_zone sdcsso0 $SDCSSO_IMAGE
[[ -n "$CLOUDAPI_IMAGE" ]] && upgrade_zone cloudapi0 $CLOUDAPI_IMAGE
[[ -n "$WORKFLOW_IMAGE" ]] && upgrade_zone workflow0 $WORKFLOW_IMAGE
[[ -n "$CNAPI_IMAGE" ]] && upgrade_zone cnapi0 $CNAPI_IMAGE
[[ -n "$DHCPD_IMAGE" ]] && upgrade_zone dhcpd0 $DHCPD_IMAGE
[[ -n "$FWAPI_IMAGE" ]] && upgrade_zone fwapi0 $FWAPI_IMAGE
[[ -n "$IMGAPI_IMAGE" ]] && upgrade_zone imgapi0 $IMGAPI_IMAGE
[[ -n "$NAPI_IMAGE" ]] && upgrade_zone napi0 $NAPI_IMAGE
[[ -n "$VMAPI_IMAGE" ]] && upgrade_zone vmapi0 $VMAPI_IMAGE
[[ -n "$UFDS_IMAGE" ]] && upgrade_zone ufds0 $UFDS_IMAGE
[[ -n "$DAPI_IMAGE" ]] && upgrade_zone dapi0 $DAPI_IMAGE
[[ -n "$PAPI_IMAGE" ]] && upgrade_zone papi0 $PAPI_IMAGE
[[ -n "$REDIS_IMAGE" ]] && upgrade_zone redis0 $REDIS_IMAGE
[[ -n "$RABBITMQ_IMAGE" ]] && upgrade_zone rabbitmq0 $RABBITMQ_IMAGE
[[ -n "$ASSETS_IMAGE" ]] && upgrade_zone assets0 $ASSETS_IMAGE
[[ -n "$CA_IMAGE" ]] && upgrade_zone ca0 $CA_IMAGE
[[ -n "$MORAY_IMAGE" ]] && upgrade_zone moray0 $MORAY_IMAGE

exit 0
