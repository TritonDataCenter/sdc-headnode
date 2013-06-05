#!/usr/bin/bash
#
# upgrade-sapi.sh: provision a new SAPI instance

set -o xtrace
set -o errexit

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <datacenter>"
    exit 1
fi

source ./images.sh

DATACENTER=$1
SAPI_URL=http://sapi.${DATACENTER}.joyent.us
APP_UUID=$(sdc-sapi /applications?name=sdc | json -Ha uuid)

if [[ -z ${SAPI_IMAGE} ]] ; then
    echo "error: \$SAPI_IMAGE not defined"
    exit 1
fi


# (1) Update SAPI application metadata with new sapi-url

echo "{
    \"metadata\": {
        \"sapi-url\": \"${SAPI_URL}\"
    }
}" > /tmp/changes.$$.json

sdc-sapi /applications/${APP_UUID} -X PUT -T /tmp/changes.$$.json


# (2) Update all SAPI service metadata with new sapi-url

for svc in $(sdc-sapi /services?application_uuid=${APP_UUID} | json -Ha uuid); do
    sdc-sapi /services/${svc} -X PUT -T /tmp/changes.$$.json
done


# (3) Update VM metadata with new sapi-url

echo "{
    \"set_customer_metadata\": {
        \"sapi-url\": \"${SAPI_URL}\"
    }
}" > /tmp/changes.$$.json

for zone in $(vmadm lookup tags.smartdc_type=core | awk '{print $1}'); do
    cat /tmp/changes.$$.json | vmadm update $zone
done


# (4) Update all the config-agent/etc/config.json to refer to the new sapi-url
# as opposed to the original IP address

for file in $(ls /zones/*/root/opt/smartdc/config-agent/etc/config.json); do
    cat $file | json -e "this.sapi.url = '${SAPI_URL}'" > /tmp/1
    mv /tmp/1 $file
done


# (5) Install latest SAPI image

./download-image.sh ${SAPI_IMAGE}


# (6) Fix up SAPI's SAPI service to refer to new image

echo "{
    \"params\": {
        \"image_uuid\": \"${SAPI_IMAGE}\"
    }
}" > /tmp/changes.$$.json

SAPI_SVC_UUID=$(sdc-sapi /services?name=sapi | json -Ha uuid | head -n 1)
sdc-sapi /services/${SAPI_SVC_UUID} -X PUT -T /tmp/changes.$$.json


# (7) Edit /usbkey/services/sapi/service.json with ^ image_uuid

# XXX I don't think this is necessary


# (8) Ensure that SAPI_MODE is set correct -- should be "full"

echo "{
    \"metadata\": {
        \"SAPI_MODE\": \"full\"
    }
}" > /tmp/changes.$$.json
sdc-sapi /services/${SAPI_SVC_UUID} -X PUT -T /tmp/changes.$$.json


# (9) Patch latest setup.common into /usbkey.  This works around HEAD-1742

cp ./setup.common /usbkey/extra/sapi/setup.common


# (10) Provision a new SAPI instance

echo "
{
    \"service_uuid\": \"${SAPI_SVC_UUID}\",
    \"params\": {
        \"alias\": \"sapi1\"
    }
}" | sapiadm provision


# (11) Restart SAPI to workaround lack of appropriate post_cmd

sleep 35
SAPI1_UUID=$(vmadm lookup alias=sapi1)
zlogin ${SAPI1_UUID} svcadm restart sapi


# (12) Destroy the original SAPI instance

SAPI0_UUID=$(vmadm lookup alias=sapi0)
SAPI1_IP=$(vmadm get $(vmadm lookup alias=sapi1) | json nics.0.ip)
curl http://${SAPI1_IP}/instances/${SAPI0_UUID} -X DELETE

sleep 60  # to allow DNS record for sapi0 to expire
