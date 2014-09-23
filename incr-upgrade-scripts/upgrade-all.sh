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
# Upgrade given SDC zones to latest images
#
# Usage:
#   ./upgrade-all.sh [-f] <upgrade-images-file>
#
# Options:
#   -f      Force reprovision even if to the same image. This will also
#           skip importing the possibly missing image into IMGAPI -- useful
#           for dealing with a broken IMGAPI, but could surprise. Lesson:
#           don't use '-f' lightly.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
#set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


PATH=/opt/smartdc/bin:$PATH

UPDATES_IMGADM='/usr/node/bin/node /opt/smartdc/imgapi-cli/bin/updates-imgadm'



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

function upgrade_zone {
    local role=$1
    local alias=$2
    local image_uuid=$3

    get_instance_uuid ${alias}
    local instance_uuid=${uuid}

    if [[ -z ${instance_uuid} ]]; then
        echo "No zone with alias ${alias}"
        return 0
    fi

    local current_image_uuid=$(vmadm get ${instance_uuid} | json -H image_uuid)
    local current_alias=$(vmadm get ${instance_uuid} | json -H alias)

    if [[ ${current_image_uuid} == ${image_uuid} && -z "$force" ]]; then
        printf "Instance %s (%s) already using image %s." \
            ${instance_uuid} ${current_alias} ${image_uuid}
        return 0
    fi

    # If 'force=true' and we already have $image_uuid in the local zpool,
    # then *skip* download-image.sh. This allows us to bypass IMGAPI in-case
    # it is broken, at the cost of not having imported it to IMGAPI.
    if [[ -n "$force" && -n "$( (imgadm get $image_uuid 2>/dev/null || true) )" ]]; then
        echo "Have image $image_uuid in local zpool and force=$force, skipping image download."
    else
        ./download-image.sh ${image_uuid} || fatal "failed to download image"
    fi

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

    update_svc_user_script ${uuid} ${image_uuid}

    # Fix up SAPI's service to refer to new image.
    service_uuid=$(sdc-sapi /instances/${uuid} | json -H service_uuid)
    cat <<EOM | sdc-sapi /services/$service_uuid -X PUT -d@-
{
    "params": {
        "image_uuid": "${image_uuid}"
    }
}
EOM

    echo '{}' | json -e "this.image_uuid = '${image_uuid}'" |
        vmadm reprovision ${instance_uuid}

    printf "Instance %s (%s) reprovisioned with image %s\n" \
        ${instance_uuid} ${current_alias} ${image_uuid}

    sleep 60  # To allow zone to start back up

    return 0
}



#---- mainline


force=
if [[ "$1" == "-f" ]]; then
    shift
    force=true
fi

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
# XXX JoshW says it's pointless to upgrade redis
# XXX Trent presumes it is currently pointless to upgrade amonredis
#
# XXX - workflow should probably go before CNAPI in general, as CNAPI fires
# off a number of sysinfo jobs.
# SAPI is upgraded separately through upgrade-sapi.sh.

[[ -n "$SDC_IMAGE" ]] && upgrade_zone sdc sdc0 $SDC_IMAGE
[[ -n "$ADMINUI_IMAGE" ]] && upgrade_zone adminui adminui0 $ADMINUI_IMAGE
[[ -n "$AMON_IMAGE" ]] && upgrade_zone amon amon0 $AMON_IMAGE
[[ -n "$AMONREDIS_IMAGE" ]] && upgrade_zone amonredis amonredis0 $AMONREDIS_IMAGE
[[ -n "$CLOUDAPI_IMAGE" ]] && upgrade_zone cloudapi cloudapi0 $CLOUDAPI_IMAGE
[[ -n "$WORKFLOW_IMAGE" ]] && upgrade_zone workflow workflow0 $WORKFLOW_IMAGE
[[ -n "$CNAPI_IMAGE" ]] && upgrade_zone cnapi cnapi0 $CNAPI_IMAGE
[[ -n "$DHCPD_IMAGE" ]] && upgrade_zone dhcpd dhcpd0 $DHCPD_IMAGE
[[ -n "$FWAPI_IMAGE" ]] && upgrade_zone fwapi fwapi0 $FWAPI_IMAGE
[[ -n "$NAPI_IMAGE" ]] && upgrade_zone napi napi0 $NAPI_IMAGE
[[ -n "$VMAPI_IMAGE" ]] && upgrade_zone vmapi vmapi0 $VMAPI_IMAGE
[[ -n "$PAPI_IMAGE" ]] && upgrade_zone papi papi0 $PAPI_IMAGE
[[ -n "$MAHI_IMAGE" ]] && upgrade_zone mahi mahi0 $MAHI_IMAGE
[[ -n "$REDIS_IMAGE" ]] && upgrade_zone redis redis0 $REDIS_IMAGE
[[ -n "$ASSETS_IMAGE" ]] && upgrade_zone assets assets0 $ASSETS_IMAGE
[[ -n "$CA_IMAGE" ]] && upgrade_zone ca ca0 $CA_IMAGE

# Guard on UFDS upgrade here so that "./upgrade-all.sh" is not used
# *directly* to upgrade UFDS. Instead use "upgrade-ufds.sh" and
# "rollback-ufds.sh".
[[ -n "$REALLY_UPGRADE_UFDS" && -n "$UFDS_IMAGE" ]] && upgrade_zone ufds ufds0 $UFDS_IMAGE
# Ditto for rabbitmq and others.
[[ -n "$REALLY_UPGRADE_RABBITMQ" && -n "$RABBITMQ_IMAGE" ]] && upgrade_zone rabbitmq rabbitmq0 $RABBITMQ_IMAGE
[[ -n "$REALLY_UPGRADE_IMGAPI" && -n "$IMGAPI_IMAGE" ]] && upgrade_zone imgapi "${IMGAPI_ALIAS:-imgapi0}" $IMGAPI_IMAGE

exit 0
