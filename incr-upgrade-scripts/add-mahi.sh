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
# Script to add "mahi" zone to an existing SDC 7.
#
#       ./add-mahi.sh IMAGE
#
# where "IMAGE" is a mahi image UUID to use. You can specify "latest"
# to use the latest mahi image *in the local IMGAPI*.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- globals

role=mahi
image_name=manta-authcache


#---- mainline

NEW_IMAGE=$1
if [[ -z "$NEW_IMAGE" ]]; then
    echo "usage: ./add-mahi.sh IMAGE"
    fatal "no IMAGE argument given"
elif [[ "$NEW_IMAGE" == "latest" ]]; then
    NEW_IMAGE=$(sdc-imgadm list --latest name=$image_name -H -o uuid)
    if [[ -z "$NEW_IMAGE" ]]; then
        fatal "no '$image_name' image found in local IMGAPI"
    fi
fi
echo "Adding 'mahi' service and instance using image $NEW_IMAGE"


./download-image.sh ${NEW_IMAGE}


SDC_APP_UUID=$(sdc-sapi --no-headers /applications?name=sdc | json 0.uuid)
DOMAIN=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name).$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)
USERSCRIPT=$(/usr/node/bin/node -e 'console.log(JSON.stringify(require("fs").readFileSync("/usbkey/default/user-script.common", "utf8")))')

# Before attempting to create the service, let's double check it doesn't exist:
SERVICE_UUID=$(sdc-sapi --no-headers /services?name=$role | json -Ha uuid)
if [[ -n "$SERVICE_UUID" ]]; then
    echo "Service $role already exists, moving into next step"
else
    json -f ./sapi/$role/"${role}"_svc.json \
      | json -e "this.application_uuid=\"$SDC_APP_UUID\"" \
      | json -e "this.metadata.SERVICE_DOMAIN=\"mahi.${DOMAIN}\"" \
      | json -e "this.params.image_uuid=\"$NEW_IMAGE\"" \
      | json -e "this.metadata[\"user-script\"]=$USERSCRIPT" \
      | json -e "this.params.delegate_dataset=true" \
      >./"${role}"-service.json

    echo "Service $role does not exist. Attempting to create it"
    SERVICE_UUID=$(sdc-sapi /services -X POST -d@./"${role}"-service.json | json -H uuid)
    echo "Service UUID is '$SERVICE_UUID'"

    cat <<EOM > ./update-sdc-app-for-$role.json
{
    "metadata" : {
        "MAHI_SERVICE" : "mahi.$DOMAIN",
        "mahi_domain" : "mahi.$DOMAIN"
    }
}
EOM
    sapiadm update $SDC_APP_UUID -f ./update-sdc-app-for-$role.json
fi

# provision!
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json |json ufds_admin_uuid)
cat <<EOM | sapiadm -v provision
{
    "service_uuid" : "$SERVICE_UUID",
    "params" : {
        "owner_uuid": "$UFDS_ADMIN_UUID",
        "alias" : "mahi0"
    }
}
EOM

echo "Done!"
exit 0
