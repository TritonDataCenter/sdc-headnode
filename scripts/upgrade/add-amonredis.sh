#!/usr/bin/bash

set -o xtrace
set -o errexit

mkdir /usbkey/extra/amonredis
cp /usbkey/extra/redis/* /usbkey/extra/amonredis
cp /zones/mbs/upgrade/zones/amonredis/* /usbkey/extra/amonredis

# add sapi service:
# get sdc uuid
SDC=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
SAPIURL=$(sdc-sapi /services?name=redis | json -Ha 'metadata["sapi-url"]')
ASSETSIP=$(sdc-sapi /services?name=redis | json -Ha 'metadata["assets-ip"]')
USERSCRIPT=$(/usr/node/bin/node -e 'console.log(JSON.stringify(require("fs").readFileSync("/usbkey/default/user-script.common", "utf8")))')
DOMAIN=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name).$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)

# update application uuid & image uuid
mkdir -p /zones/mbs/upgrade/tmp
json -f /zones/mbs/upgrade/sapi/amonredis/amonredis_svc.json \
    | json -e "application_uuid=\"$SDC\"" \
    | json -e 'params.image_uuid="9b7f624b-6980-4059-8942-6be33c4f54d6"' \
    | json -e "metadata[\"sapi-url\"]=\"$SAPIURL\"" \
    | json -e "metadata[\"assets-ip\"]=\"$ASSETSIP\"" \
    | json -e "metadata[\"user-script\"]=$USERSCRIPT" \
    | json -e "metadata[\"SERVICE_DOMAIN\"]=\"amonredis.${DOMAIN}\"" \
    > /zones/mbs/upgrade/tmp/service.json


cat <<EOM > /zones/mbs/upgrade/tmp/svc.json
{
    "metadata" : {
        "AMONREDIS_SERVICE" : "amonredis.$DOMAIN",
        "amonredis_domain" : "amonredis.$DOMAIN"
    }
}
EOM
sapiadm update $SDC -f /zones/mbs/upgrade/tmp/svc.json

# add new service
S_UUID=$(sdc-sapi /services -X POST -d@/zones/mbs/upgrade/tmp/service.json | json -H uuid)

# add manifest
M_UUID=$(sdc-sapi /manifests -X POST -d@/zones/mbs/upgrade/sapi/amonredis/manifest.json | json -H uuid)
sdc-sapi /services/$S_UUID -X PUT -d"{\"manifests\":{\"redis\":\"$M_UUID\"}}"

# provision!
cat <<EOM | sapiadm provision
{
    "service_uuid" : "$S_UUID",
    "params" : {
        "alias" : "amonredis0"
    }
}
EOM

# check
