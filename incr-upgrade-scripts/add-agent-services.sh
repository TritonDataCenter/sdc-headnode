#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
if [[ ! -f "$TOP/upgrade-all.sh" ]]; then
    echo "$0: fatal error: must run this from the incr-upgrade dir" >&2
    exit 1
fi

SDCAPP=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
MIN_VALID_SAPI_VERSION=20140703

# SAPI versions can have the following two forms:
#
#   release-20140724-20140724T171248Z-gf4a5bed
#   master-20140724T174534Z-gccfea7e
#
# We need at least a MIN_VALID_SAPI_VERSION image so type=agent suport is there.
# When the SAPI version doesn't match the expected format we ignore this script
#
valid_sapi=$(sdc-imgadm get $(sdc-vmapi /vms/$(vmadm lookup alias=~^sapi) | json -H image_uuid) \
    | json -e \
    "var splitVersion = this.version.split('-');
    if (splitVersion[0] === 'master') {
        this.validSapi = splitVersion[1].substr(0, 8) >= '$MIN_VALID_SAPI_VERSION';
    } else if (splitVersion[0] === 'release') {
        this.validSapi = splitVersion[1] >= '$MIN_VALID_SAPI_VERSION';
    } else {
        this.validSapi = false;
    }
    " | json validSapi)

if [[ ${valid_sapi} == "false" ]]; then
    echo "Datacenter does not have the minimum SAPI version needed for adding
        service agents. No need to run add-agent-services.sh"
    exit 0
fi

function service_exists()
{
    local service_name=$1
    local service_uuid=$(sdc-sapi "/services?name=$service_name&type=agent" | json -Ha uuid)

    if [[ -n ${service_uuid} ]]; then
        return 0
    else
        return 1
    fi
}

# Add the SAPI service
SERVICES="vm-agent net-agent cn-agent"
for service in $SERVICES; do
    if ! service_exists "$service"; then
        json -f ./sapi/$service/service.json \
            | json -e "this.application_uuid=\"$SDCAPP\"" \
            > ./$service-service.json
        sdc-sapi /services -X POST -d@./$service-service.json
        echo "Service $service added to SAPI"
    else
        echo "Service $service exists already"
    fi
done
