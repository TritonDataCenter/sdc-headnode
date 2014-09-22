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
# upgrade-mahi:
#   - add delegated dataset to mahi zone if none exists
#   - reprovision mahi


export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh

#---- mainline

# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-mahi.sh <upgrade-images-file>"
    exit 1
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1
if [[ -z ${MAHI_IMAGE} ]]; then
    fatal "\$MAHI_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~^mahi)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running mahiN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)
DATASET="zones/$CUR_UUID/data"

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $MAHI_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi

# -- Get the new image.
./download-image.sh ${MAHI_IMAGE}
[[ $? == 0 ]] || fatal "Unable to download/install mahi image $MAHI_IMAGE"

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' MAHI app"
MAHI_JSON=$(sdc-sapi /services?name=mahi\&application_uuid=$SDC_APP | json -Ha)
[[ -n "$MAHI_JSON" ]] || fatal "could not fetch sdc 'mahi' MAHI service"
MAHI_SVC=$(echo "$MAHI_JSON" | json uuid)
[[ -n "$MAHI_SVC" ]] || fatal "could not determine sdc 'mahi' MAHI service"

ensure_delegated_dataset "mahi" "false"
[[ $? == 0 ]] || fatal "could not ensure mahi delegated dataset"

# -- Update service data in MAHI.
update_svc_user_script $CUR_UUID $MAHI_IMAGE
sapiadm update $MAHI_SVC params.image_uuid=$MAHI_IMAGE

# move the redis db to the delegated dataset if we need to
if [[ -e /zones/$CUR_UUID/root/var/db/redis/dump.db ]]; then
    zlogin $CUR_UUID "svcadm disable -s mahi-server && \
                      svcadm disable -s mahi-replicator && \
                      touch /var/db/redis/.moved && \
                      cp -a /var/db/redis/dump.db /mahi/redis && \
                      svcadm enable -s mahi-replicator && \
                      svcadm enable -s mahi-server"
fi

sapiadm reprovision $CUR_UUID $MAHI_IMAGE

echo "Done mahi upgrade."
