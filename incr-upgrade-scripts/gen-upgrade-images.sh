#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Helper script to generate an 'upgrade-images' file to be used for
# an SDC upgrade.
#
# Usage:
#       ./gen-upgrade-images.sh [SERVICES...]
#
# By default this will find the latest image for *all* services (with some
# exceptions for services that are typically not upgraded). A subset of
# service names can be specified, e.g.:
#
#       ./gen-upgrade-images.sh imgapi vmapi
#


if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}




#---- mainline

services=$*
if [[ -z "$services" ]]; then
    # If running in usb-headnode.git clone, then use list of services in
    # config dir.
    if [[ -d "$TOP/../config/sapi/services" ]]; then
        services=$(ls -1 $TOP/../config/sapi/services)
    # If running on a setup SDC headnode, then use the list of services in
    # SAPI.
    elif [[ -n "$(sdc-sapi /applications?name=sdc | json -H 0.uuid || true)" ]]; then
        sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
        services=$(sdc-sapi "/services?application_uuid=$sdc_app&type=vm" | json -Ha name)
    fi
    # Excluded by default:
    # - redis, amonredis: typically don't need to upgrade these
    # - binder, dhcpd: don't have upgrade logic for these. ZK in binder to fear
    # - manatee, moray: typically HA, don't have automatic upgrade logic for
    #   those upgrades
    # - manta: typically handled for manta upgrade handling
    # - sdcsso: no longer part of sdc core
    services=$(echo "$services" \
        | grep -v amonredis \
        | grep -v binder \
        | grep -v dapi \
        | grep -v dhcpd \
        | grep -v manta \
        | grep -v manatee \
        | grep -v moray \
        | grep -v redis \
        | grep -v sdcsso \
        | sort \
        | xargs)
fi
#echo "services: '$services'


for service in $services; do
    # Map service to image name.
    image_name=$service
    if [[ $service == "moray" ]]; then
        image_name=manta-moray
    elif [[ $service == "manta" ]]; then
        image_name=manta-deployment
    elif [[ $service == "binder" ]]; then
        image_name=manta-nameservice
    elif [[ $service == "manatee" ]]; then
        image_name=sdc-postgres
    elif [[ $service == "mahi" ]]; then
        image_name=manta-authcache
    fi
    #echo "# get latest '$image_name' image for service '$service'" 2>&1
    image_data=$(updates-imgadm list --latest -j version=~master name=$image_name | json -- -1)
    image_uuid=$(echo "$image_data" | json uuid)
    image_version=$(echo "$image_data" | json version)
    printf "export %9s_IMAGE=%s  # version=%s image_name=%s\n" \
        $(echo $service | tr 'a-z' 'A-Z') $image_uuid $image_version $image_name
done

