#!/usr/bin/bash
#
# upgrade-sapi.sh:
#   - provision sapi1 zone and wait until in DNS (presuming curr SAPI is 'sapi0')
#   - stop sapi0 zone
#   - upgrade sapi0 and wait until in DNS
#   - destroy sapi1
#
# We do this dance because upgrading SAPI in "full" mode requires a SAPI around.

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- mainline

# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-sapi.sh <upgrade-images-file>"
    exit 1
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1
if [[ -z ${SAPI_IMAGE} ]]; then
    fatal "\$SAPI_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~^sapi)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running sapiN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $SAPI_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi


SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
SAPI_JSON=$(sdc-sapi /services?name=sapi\&application_uuid=$SDC_APP | json -Ha)
[[ -n "$SAPI_JSON" ]] || fatal "could not fetch sdc 'sapi' SAPI service"
SAPI_SVC=$(echo "$SAPI_JSON" | json uuid)
[[ -n "$SAPI_SVC" ]] || fatal "could not determine sdc 'sapi' SAPI service"
SAPI_DOMAIN=$(bash /lib/sdc/config.sh -json | json sapi_domain)
[[ -n "$SAPI_DOMAIN" ]] || fatal "no 'sapi_domain' in sdc config"

CUR_MODE=$(sdc-sapi --no-headers /mode)
[[ "$CUR_MODE" == "full" ]] \
    || fatal "SAPI is not in 'full' mode ($CUR_MODE). Cannot upgrade this."


# -- Get sapi past SAPI-219 (adding a delegate dataset)
HAS_DATASET=$(echo "$SAPI_JSON" | json params.delegate_dataset)
if [[ "$HAS_DATASET" != "true" ]]; then
    echo '{ "params": { "delegate_dataset": true } }' | \
        sapiadm update "$SAPI_SVC"
    [[ $? == 0 ]] || fatal "Unable to set delegate_dataset on sapi service."

    # -- Verify it got there
    SAPI_JSON=$(sdc-sapi /services?name=sapi\&application_uuid=$SDC_APP | \
        json -Ha)
    [[ -n "$SAPI_JSON" ]] || fatal "could not fetch sdc 'sapi' SAPI service"
    HAS_DATASET=$(echo "$SAPI_JSON" | json params.delegate_dataset)
    [[ "$HAS_DATASET" == "true" ]] || \
        fatal "sapiadm updated the sapi service but it didn't take"
fi

# -- Add a delegated dataset to current sapi, if needed (more SAPI-219).
DATASET="zones/$CUR_UUID/data"
VMAPI_DATASET=$(sdc-vmapi /vms/$CUR_UUID | json -Ha datasets.0)
if [[ "$DATASET" != "$VMAPI_DATASET" ]]; then
    zfs list "$DATASET" && rc=$? || rc=$?
    if [[ $rc != 0 ]]; then
        zfs create $DATASET
        [[ $? == 0 ]] || fatal "Unable to create sapi zfs dataset"
    fi

    zfs set zoned=on $DATASET
    [[ $? == 0 ]] || fatal "Unable to set zoned=on on sapi dataset"

    zonecfg -z $CUR_UUID "add dataset; set name=${DATASET}; end"
    [[ $? == 0 ]] || fatal "Unable to set dataset on sapi zone"

    VMADM_DATASET=$(vmadm get $CUR_UUID | json datasets.0)
    [[ "$DATASET" == "$VMADM_DATASET" ]] || \
        fatal "Set dataset on sapi zone, but getting did not work"

    # The reprovision will mount it on restart.
fi


# -- Get the new image.
./download-image.sh ${SAPI_IMAGE}
[[ $? == 0 ]] || fatal "Unable to download/install sapi image $SAPI_IMAGE"


# -- Provision a new upgraded zone.

# Update service data in SAPI.
sapiadm update $SAPI_SVC params.image_uuid=$SAPI_IMAGE
update_svc_user_script $CUR_UUID $SAPI_IMAGE

# Workaround SAPI-199.
SAPI_URL="http://$SAPI_DOMAIN"
sapiadm update $SAPI_SVC metadata.sapi-url=$SAPI_URL   # workaround SAPI-199
echo "{\"set_customer_metadata\": {\"sapi-url\": \"$SAPI_URL\"}}" |
    vmadm update ${CUR_UUID}

# Provision a new instance.
CUR_N=$(echo $CUR_ALIAS | sed -E 's/sapi([0-9]+)/\1/')
NEW_N=$(( $CUR_N + 1 ))
NEW_ALIAS=sapi$NEW_N
cat <<EOM | sapiadm provision
{
    "service_uuid": "$SAPI_SVC",
    "params": {
        "owner_uuid": "$UFDS_ADMIN_UUID",
        "alias": "$NEW_ALIAS"
    }
}
EOM
NEW_UUID=$(vmadm lookup -1 owner_uuid=$UFDS_ADMIN_UUID alias=$NEW_ALIAS)
[[ -n "$NEW_UUID" ]] || fatal "could not find new $NEW_ALIAS zone"

# Wait for new IP to enter DNS.
wait_until_zone_in_dns $NEW_UUID $NEW_ALIAS $SAPI_DOMAIN


# -- Phase out the "NEW" sapi zone. Just want to keep the original "CUR" one.

CUR_IP=$(vmadm get $CUR_UUID | json nics.0.ip)
NEW_IP=$(vmadm get $NEW_UUID | json nics.0.ip)

# TODO: instead of waiting to get out of DNS, then back in, would be faster
#    to not bother and just wait until a ping check on the sapi service is
#    up.
zlogin ${CUR_UUID} svcadm disable registrar
wait_until_zone_out_of_dns $CUR_UUID $CUR_ALIAS $SAPI_DOMAIN $CUR_IP

# Add "SAPI_MODE" to workaround SAPI-197. This will be unnecessary on SAPI
# images after SAPI-167/SAPI-211 (where "SAPI_MODE" is replaced by
# "SAPI_PROTO_MODE=true").
echo '{"set_customer_metadata": {"SAPI_MODE": "full"}}' |
    vmadm update ${CUR_UUID}

echo '{}' | json -e "this.image_uuid = '${SAPI_IMAGE}'" |
    vmadm reprovision ${CUR_UUID}
wait_until_zone_in_dns $CUR_UUID $CUR_ALIAS $SAPI_DOMAIN $CUR_IP

curl http://$CUR_IP/instances/$NEW_UUID -X DELETE
wait_until_zone_out_of_dns $NEW_UUID $NEW_ALIAS $SAPI_DOMAIN $NEW_IP

# Because we shuffle back to sapi0 we don't need to update to 'sapiadm'
# symlink. In case that fails and you are stuck with sapi1, this might be
# useful:
#    SAPI_UUID=$(vmadm lookup alias=~sapi)
#    rm -f /opt/smartdc/bin/sapiadm
#    ln -s /zones/${SAPI_UUID}/root/opt/smartdc/config-agent/cmd/sapiadm.js \
#        /opt/smartdc/bin/sapiadm

# Run the SAPI backfill script if available
zlogin ${CUR_UUID} /usr/bin/bash <<HERE
if [[ -f /opt/smartdc/sapi/tools/sapi-backfill-service-type.js ]]; then
    /opt/smartdc/sapi/build/node/bin/node /opt/smartdc/sapi/tools/sapi-backfill-service-type.js
fi

if [[ -f /opt/smartdc/sapi/tools/sapi-backfill-instance-type.js ]]; then
    /opt/smartdc/sapi/build/node/bin/node /opt/smartdc/sapi/tools/sapi-backfill-instance-type.js
fi
HERE

echo "Done sapi upgrade."
