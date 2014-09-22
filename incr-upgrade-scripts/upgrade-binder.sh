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
# upgrade-binder.sh:
#   - get current binder past flag days
#   - reprovision binder

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- mainline

# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-binder.sh <upgrade-images-file>"
    exit 1
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1
if [[ -z ${BINDER_IMAGE} ]]; then
    fatal "\$BINDER_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~^binder)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running binderN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)
DATASET="zones/$CUR_UUID/data"

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $BINDER_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi


# -- Get the new image.
./download-image.sh ${BINDER_IMAGE}
[[ $? == 0 ]] || fatal "Unable to download/install binder image $BINDER_IMAGE"


SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' BINDER app"
BINDER_JSON=$(sdc-sapi /services?name=binder\&application_uuid=$SDC_APP | json -Ha)
[[ -n "$BINDER_JSON" ]] || fatal "could not fetch sdc 'binder' BINDER service"
BINDER_SVC=$(echo "$BINDER_JSON" | json uuid)
[[ -n "$BINDER_SVC" ]] || fatal "could not determine sdc 'binder' BINDER service"


# -- Get binder past MANTA-2297 (adding a delegate dataset)
ensure_delegated_dataset "binder" "true"
[[ $? == 0 ]] || fatal "could not ensure binder delegated dataset"


# -- Update service data in BINDER.
update_svc_user_script $CUR_UUID $BINDER_IMAGE
sapiadm update $BINDER_SVC params.image_uuid=$BINDER_IMAGE

# -- Upgrade zone.

# Move the zk db to the delegated dataset (if we need to, more MANTA-2297)
if [[ -e /zones/$CUR_UUID/root/var/db/zookeeper/myid ]]; then
    zlogin $CUR_UUID "svcadm disable -s zookeeper && \
                      touch /var/db/zookeeper/.moved && \
                      cp -a /var/db/zookeeper /$DATASET/. && \
                      svcadm enable -s zookeeper"
    echo 'Sleeping to let ZK come back'
    sleep 90
fi

sapiadm reprovision $CUR_UUID $BINDER_IMAGE

echo "Done binder upgrade."
