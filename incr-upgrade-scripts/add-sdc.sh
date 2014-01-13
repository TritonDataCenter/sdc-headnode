#!/usr/bin/bash
#
# Add a new 'sdc' core zone.
#

set -o xtrace
set -o errexit

# add sapi service:
SDCAPP=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
SAPIURL=$(sdc-sapi /services?name=redis | json -Ha 'metadata["sapi-url"]')
ASSETSIP=$(sdc-sapi /services?name=redis | json -Ha 'metadata["assets-ip"]')
USERSCRIPT=$(/usr/node/bin/node -e 'console.log(JSON.stringify(require("fs").readFileSync("/usbkey/default/user-script.common", "utf8")))')
DOMAIN=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name).$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)
IMAGE_UUID=$(sdc-imgadm list name=sdc -H -o uuid | tail -1)
BILLING_ID=$(sdc-ldap search '(&(objectclass=sdcpackage)(name=sdc_768))' | grep '^uuid' | cut -d' ' -f2)

if [[ -z "$IMAGE_UUID" ]]; then
    echo "$0: fatal error: no 'sdc' image uuid in IMGAPI to use"
    exit 1
fi

# We have a commited manually hacked version of the 'sdc' service JSON.
# Some of those fields from usb-headnode/config/sapi/services/sdc/service.json
# and some from fields that core zone setup would fill in from the package used.
#
# The *right* answer here is to pull many of the "params" from the appropriate
# package.
json -f ./sapi/sdc/sdc_svc.json \
    | json -e "application_uuid=\"$SDCAPP\"" \
    | json -e "params.image_uuid=\"$IMAGE_UUID\"" \
    | json -e "params.billing_id=\"$BILLING_ID\"" \
    | json -e "metadata[\"sapi-url\"]=\"$SAPIURL\"" \
    | json -e "metadata[\"assets-ip\"]=\"$ASSETSIP\"" \
    | json -e "metadata[\"user-script\"]=$USERSCRIPT" \
    | json -e "metadata[\"SERVICE_DOMAIN\"]=\"sdc.${DOMAIN}\"" \
    >./sdc-service.json
SERVICE_UUID=$(sdc-sapi /services -X POST -d@./sdc-service.json | json -H uuid)

cat <<EOM > ./update-sdc-app.json
{
    "metadata" : {
        "SDC_SERVICE" : "sdc.$DOMAIN",
        "sdc_domain" : "sdc.$DOMAIN"
    }
}
EOM
sapiadm update $SDCAPP -f ./update-sdc-app.json


# new 'sdc' tool in /opt/smartdc/bin
cp ./tools/sdc /opt/smartdc/bin/sdc


# provision!
cat <<EOM | sapiadm provision
{
    "service_uuid" : "$SERVICE_UUID",
    "params" : {
        "alias" : "sdc0"
    }
}
EOM


# Workaround for HEAD-1813: Add an external nic that is the primary so it is the
# default gateway, but NOT first so that its resolvers are not first.
sdc-vmapi /vms/$(vmadm lookup -1 alias=sdc0)?action=add_nics -X POST -d@- <<EOP
{
    "networks": [{"uuid": "$(sdc-napi /networks?name=external | json -H 0.uuid)", "primary": true}]
}
EOP
sleep 10



# Add the new SDC *app* manifests for the sdc key that the 'sdc' zone creates.
sdc_app_uuid=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)

sdc_private_key_uuid=$(uuid)
sdc-sapi /manifests -X POST -d@- <<EOP
{
    "uuid": "$sdc_private_key_uuid",
    "name": "sdc_private_key",
    "path": "/root/.ssh/sdc.id_rsa",
    "post_cmd": "chmod 600 /root/.ssh/sdc.id_rsa",
    "template": "{{{SDC_PRIVATE_KEY}}}"
}
EOP
sdc-sapi /applications/$sdc_app_uuid -X PUT -d@- <<EOP
{
    "manifests": {
        "sdc_private_key": "$sdc_private_key_uuid"
    }
}
EOP

sdc_public_key_uuid=$(uuid)
sdc-sapi /manifests -X POST -d@- <<EOP
{
    "uuid": "$sdc_public_key_uuid",
    "name": "sdc_public_key",
    "path": "/root/.ssh/sdc.id_rsa.pub",
    "post_cmd": "touch /root/.ssh/authorized_keys; sed -i '.bak' -e '/ sdc key$/d' /root/.ssh/authorized_keys; echo '' >>/root/.ssh/authorized_keys; cat /root/.ssh/sdc.id_rsa.pub >>/root/.ssh/authorized_keys",
    "template": "{{{SDC_PUBLIC_KEY}}}"
}
EOP
sdc-sapi /applications/$sdc_app_uuid -X PUT -d@- <<EOP
{
    "manifests": {
        "sdc_public_key": "$sdc_public_key_uuid"
    }
}
EOP
