#!/usr/bin/bash
#
# upgrade-ufds.sh:
#   - NOTE: If this is the UFDS master, then, in general, all slaves should
#     disable ufds-replicator until they themselves have been upgraded.
#     Typically this should only be required for UFDS postgres schema
#     migrations.
#   - TODO: can we put portal in RO mode?
#   - moray backup of ufds buckets
#   - provision ufds1 zone and wait until in DNS (presuming curr UFDS is 'ufds0')
#   - stop ufds0 zone
#   - run `backfill` in moray zone (the backfill script is to fill in values
#     for newly added indexes in the UFDS bucket in moray)
#   - upgrade ufds0 and wait until in DNS
#   - stop ufds1 (we don't need it anymore, delete it eventually)
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}


#XXX move this to libupgrade
# Update the customer_metadata.user-script on a zone in preparation for
# 'vmadm reprovision'. Also save it in "user-scripts/" for possible rollback.
function update_svc_user_script {
    local uuid=$1
    local image_uuid=$2
    local current_image_uuid=$(vmadm get $uuid | json image_uuid)

    # If we have a user-script for this zone/image here we must be doing a
    # rollback so we want to use that user-script. If we don't have one, we
    # save the current one for future rollback.
    mkdir -p user-scripts
    if [[ -f user-scripts/${alias}.${image_uuid}.user-script ]]; then
        NEW_USER_SCRIPT=user-scripts/${alias}.${image_uuid}.user-script
    else
        vmadm get ${uuid} | json customer_metadata."user-script" \
            > user-scripts/${alias}.${current_image_uuid}.user-script
        [[ -s user-scripts/${alias}.${current_image_uuid}.user-script ]] \
            || fatal "Failed to create ${alias}.${current_image_uuid}.user-script"

        if [[ -f /usbkey/default/user-script.common ]]; then
            NEW_USER_SCRIPT=/usbkey/default/user-script.common
        else
            fatal "Unable to find user-script for ${alias}"
        fi
    fi
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} | vmadm update ${uuid}

    # Update user-script for future provisions.
    mkdir -p sapi-updates
    local service_uuid=$(sdc-sapi /instances/${uuid} | json -H service_uuid)
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} \
        | json -e "this.payload={metadata: this.set_customer_metadata}" payload \
        > sapi-updates/${service_uuid}.update
    sdc-sapi /services/${service_uuid} -X PUT -d @sapi-updates/${service_uuid}.update
}



#---- mainline


# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    fatal "Usage: upgrade-ufds.sh upgrade-images"
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1

if [[ -z ${UFDS_IMAGE} ]]; then
    fatal "\$UFDS_IMAGE not defined"
fi
[[ $(hostname) == "headnode" ]] || fatal "not running on the headnode"

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
UFDS_SVC=$(sdc-sapi /services?name=ufds\&application_uuid=$SDC_APP | json -H 0.uuid)
[[ -n "$UFDS_SVC" ]] || fatal "could not determine sdc 'ufds' SAPI service"
UFDS_DOMAIN=$(bash /lib/sdc/config.sh -json | json ufds_domain)
[[ -n "$UFDS_DOMAIN" ]] || fatal "no 'ufds_domain' in sdc config"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~ufds)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running ufdsN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $UFDS_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi


# -- Get the new image.
./download-image.sh $UFDS_IMAGE || fatal "failed to download image $UFDS_IMAGE"


# -- Do the UFDS upgrade.

# Backup data.
sdc-login manatee "pg_dump -U moray -t 'ufds*' moray" >./moray_ufds_backup.sql


# Update UFDS service in SAPI.
# WARNING: hardcoded values here, should really derive from canonical ufds
# service JSON somewhere.
sapiadm update $UFDS_SVC params.max_physical_memory=8192
sapiadm update $UFDS_SVC params.max_locked_memory=8192
sapiadm update $UFDS_SVC params.max_swap=8448
sapiadm update $UFDS_SVC params.image_uuid=$UFDS_IMAGE
update_svc_user_script $CUR_UUID $UFDS_IMAGE

# Provision a new ufds instance.
CUR_N=$(echo $CUR_ALIAS | sed -E 's/ufds([0-9]+)/\1/')
NEW_N=$(( $CUR_N + 1 ))
NEW_ALIAS=ufds$NEW_N
cat <<EOM | sapiadm provision
{
    "service_uuid": "$UFDS_SVC",
    "params": {
        "owner_uuid": "$UFDS_ADMIN_UUID",
        "alias": "$NEW_ALIAS"
    }
}
EOM
NEW_UUID=$(vmadm lookup -1 alias=$NEW_ALIAS)
[[ -n "$NEW_UUID" ]] || fatal "could not find new $NEW_ALIAS zone"

# Wait for new IP to enter DNS.
wait_until_zone_in_dns $NEW_UUID $NEW_ALIAS $UFDS_DOMAIN

# Stop old ufds.
vmadm stop $CUR_UUID


# Backfill.
# Work around EPIPE in 'vmadm lookup' (OS-2604)
MORAY_UUIDS=$(vmadm lookup alias=~^moray owner_uuid=$UFDS_ADMIN_UUID state=running)
MORAY_UUID=$(echo "$MORAY_UUIDS" | head -1)
echo "Backfill (stage 1)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    -P objectclass=sdcimage \
    -P objectclass=sdcpackage \
    -P objectclass=amonprobe \
    -P objectclass=amonprobegroup \
    -P objectclass=datacenter \
    -P objectclass=authdev \
    -P objectclass=foreigndc \
    ufds_o_smartdc </dev/null

echo "Backfill (stage 2)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    -P objectclass=sdckey \
    ufds_o_smartdc </dev/null


# Upgrade "old" ufds zone.
# TODO: I *believe* we can have two UFDS' running during backfill.
echo '{}' | json -e "this.image_uuid = '${UFDS_IMAGE}'" |
    vmadm reprovision ${CUR_UUID}


echo "Backfill (stage 3)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    ufds_o_smartdc </dev/null


# -- Phase out the "NEW" ufds zone. Just want to keep the original "CUR" one.
wait_until_zone_in_dns $CUR_UUID $CUR_ALIAS $UFDS_DOMAIN
zlogin $NEW_UUID svcadm disable registrar
wait_until_zone_out_of_dns $NEW_UUID $NEW_ALIAS $UFDS_DOMAIN
vmadm stop $NEW_UUID

set +o xtrace
echo ''
echo '* * *'
echo "Run the following to destroy the $NEW_ALIAS instance used for upgrade."
echo 'This is not done automatically because paranoia. It has been stopped.'
echo "    sdc-sapi /instances/$NEW_UUID -X DELETE"
echo '* * *'
echo "Done."
