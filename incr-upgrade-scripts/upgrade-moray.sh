#!/usr/bin/bash
#
# upgrade-moray.sh: provision a new moray on the HN, then delete the old
# one once the new one is in DNS.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail


function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}



#---- mainline

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-moray.sh upgrade-images"
    exit 1
fi

IMAGE_LIST=$1
source $IMAGE_LIST

if [[ -z ${MORAY_IMAGE} ]]; then
    fatal "\$MORAY_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old moray. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json |json ufds_admin_uuid)
CURRENT_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~moray)
[[ -n "${CURRENT_UUID}" ]] \
    || fatal "there is not exactly one running morayN zone";
CURRENT_ALIAS=$(vmadm get $CURRENT_UUID | json alias)
CURRENT_IMAGE=$(vmadm get $CURRENT_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CURRENT_IMAGE == $MORAY_IMAGE ]]; then
    echo "$0: already using image $CURRENT_IMAGE for zone $CURRENT_UUID ($CURRENT_ALIAS)"
    exit 0
fi

./download-image.sh ${MORAY_IMAGE}


# Fix up SAPI's moray service to refer to new image.
# Be careful to use the moray service for the *sdc* application, not manta's.
SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
MORAY_SVC=$(sdc-sapi /services?name=moray\&application_uuid=$SDC_APP | json -H 0.uuid)
[[ -n "$MORAY_SVC" ]] || fatal "could not determine sdc 'moray' SAPI service"
cat <<EOM | sdc-sapi /services/$MORAY_SVC -X PUT -d@-
{
    "params": {
        "image_uuid": "$MORAY_IMAGE"
    }
}
EOM

# Add new required metadata if necessary.
MORAY_MAX_PG_CONNS=$(sdc-sapi /services/$MORAY_SVC | json -H metadata.MORAY_MAX_PG_CONNS)
if [[ -z "$MORAY_MAX_PG_CONNS" ]]; then
    cat <<EOM | sdc-sapi /services/$MORAY_SVC -X PUT -d@-
{
    "metadata": {
        "MORAY_MAX_PG_CONNS": 15
    }
}
EOM
fi


# Since we're making a new zone, use the latest user-script.
if [[ -f /usbkey/default/user-script.common ]]; then
    NEW_USER_SCRIPT=/usbkey/default/user-script.common
else
    fatal "Unable to find user-script for ${alias}"
fi
/usr/vm/sbin/add-userscript /usbkey/default/user-script.common \
    | json -e "this.payload={metadata: this.set_customer_metadata}" payload \
    | sdc-sapi /services/$MORAY_SVC -X PUT -d@-


# Provision a new moray instance
CURR_N=$(echo $CURRENT_ALIAS | sed -E 's/moray([0-9]+)/\1/')
NEW_N=$(( $CURR_N + 1 ))
NEW_ALIAS=moray$NEW_N
cat <<EOM | sapiadm provision
{
    "service_uuid": "$MORAY_SVC",
    "params": {
        "owner_uuid": "$UFDS_ADMIN_UUID",
        "alias": "$NEW_ALIAS"
    }
}
EOM
NEW_UUID=$(vmadm lookup -1 alias=$NEW_ALIAS)
[[ -n "$NEW_UUID" ]] || fatal "could not find new $NEW_ALIAS zone"


# Poorman's wait for new moray to setup.
sleep 30
NEW_SVC_ERRS=$(svcs -z $NEW_UUID -x)
if [[ -n "$NEW_SVC_ERRS" ]]; then
    echo "$NEW_SVC_ERRS" >&2
    fatal "new $NEW_ALIAS ($NEW_UUID) zone has svc errors"
fi

# Poorman's wait for new moray to show up in DNS.
NEW_IP=$(vmadm get $NEW_UUID | json nics.0.ip)
[[ -n "$NEW_IP" ]] || fatal "no IP for the new $NEW_ALIAS ($NEW_UUID) zone"
MORAY_DOMAIN=$(bash /lib/sdc/config.sh -json | json moray_domain)
[[ -n "$MORAY_DOMAIN" ]] || fatal "no 'moray_domain' in sdc config"
sleep 60  # Lame sleep to wait for new moray to get in DNS.
dig $MORAY_DOMAIN +short | grep $NEW_IP


# Take the original moray out of DNS.
zlogin $CURRENT_UUID svcadm disable registrar
echo "Give it two minutes for $CURRENT_ALIAS to drop out of DNS: 'dig $MORAY_DOMAIN +short | grep -v $NEW_IP'"
sleep 120  # Lame sleep instead of polling.
EXTRA_IPS=$(dig $MORAY_DOMAIN +short | (grep -v $NEW_IP || true))
[[ -z "$EXTRA_IPS" ]] || fatal "old $CURRENT_ALIAS zone is not out of DNS: 'dig $MORAY_DOMAIN +short'"


# TODO: Destroy the original Moray instance.
# For now we just stop the origin moray zone and show the commands to fully
# destroy it.
vmadm stop $CURRENT_UUID
MORAY_SVC_MANIFESTS=$(sdc-sapi /services/$MORAY_SVC | json -H  manifests \
    | json -e 'this._=Object.keys(this).map(function (k) { return this[k] })' _  \
    | json -a | xargs)

set +o xtrace
echo ''
echo '* * *'
echo 'Run the following to destroy to original moray instance.'
echo 'This is not done automatically because paranoia. It has been stopped.'
echo "    sdc-sapi /instances/$CURRENT_UUID -X DELETE"
if [[ -n "$MORAY_SVC_MANIFESTS" ]]; then
    echo ''
    echo 'Then delete any the (now obsolete) moray SAPI service manifests:'
    for uuid in $MORAY_SVC_MANIFESTS; do
        echo "    sdc-sapi /manifests/$uuid -X DELETE"
    done
    echo "    sdc-sapi /services/$MORAY_SVC | json -He 'this._={manifests:this.manifests}' _ | sdc-sapi /services/$MORAY_SVC -X PUT -d@-"
fi
echo '* * *'

