#!/usr/bin/bash
#
# Limitation: billing_id on the SDC service is probably wrong for other DCs.
#

set -o xtrace
set -o errexit

mkdir /usbkey/extra/sdc
cp ./zones/sdc/* /usbkey/extra/sdc/
# We're not filling in 'zoneconfig', but that is deprecated.
cp /usbkey/default/setup.common /usbkey/extra/sdc/
cp /usbkey/default/configure.common /usbkey/extra/sdc/
cp /usbkey/rc/zone.root.bashrc /usbkey/extra/sdc/bashrc

# add sapi service:
SDCAPP=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
SAPIURL=$(sdc-sapi /services?name=redis | json -Ha 'metadata["sapi-url"]')
ASSETSIP=$(sdc-sapi /services?name=redis | json -Ha 'metadata["assets-ip"]')
USERSCRIPT=$(/usr/node/bin/node -e 'console.log(JSON.stringify(require("fs").readFileSync("/usbkey/default/user-script.common", "utf8")))')
DOMAIN=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name).$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)

# We have a commited manually hacked version of the 'sdc' service JSON.
# Some of those fields from usb-headnode/config/sapi/services/sdc/service.json
# and some from fields that core zone setup would fill in from the package used.
json -f ./sapi/sdc/sdc_svc.json \
    | json -e "application_uuid=\"$SDCAPP\"" \
    | json -e 'params.image_uuid="9b7f624b-6980-4059-8942-6be33c4f54d6"' \
    | json -e "metadata[\"sapi-url\"]=\"$SAPIURL\"" \
    | json -e "metadata[\"assets-ip\"]=\"$ASSETSIP\"" \
    | json -e "metadata[\"user-script\"]=$USERSCRIPT" \
    | json -e "metadata[\"SERVICE_DOMAIN\"]=\"sdc.${DOMAIN}\"" \
    >./sdc-service.json
SDCSVC=$(sdc-sapi /services -X POST -d@./sdc-service.json | json -H uuid)

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
    "service_uuid" : "$SDCSVC",
    "params" : {
        "alias" : "sdc0"
    }
}
EOM

