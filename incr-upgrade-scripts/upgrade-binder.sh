#!/usr/bin/bash
#
# upgrade-binder.sh:
#   - get current binder past flag days
#   - reprovision binder

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- mainline

# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-binder.sh <upgrade-images-file>"
    exit 1
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1
if [[ -z ${BINDER_IMAGE} ]]; then
    fatal "\$BINDER_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~^binder)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running binderN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $BINDER_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi


SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' BINDER app"
BINDER_JSON=$(sdc-sapi /services?name=binder\&application_uuid=$SDC_APP | json -Ha)
[[ -n "$BINDER_JSON" ]] || fatal "could not fetch sdc 'binder' BINDER service"
BINDER_SVC=$(echo "$BINDER_JSON" | json uuid)
[[ -n "$BINDER_SVC" ]] || fatal "could not determine sdc 'binder' BINDER service"

# -- Get binder past MANTA-2297 (adding a delegate dataset)
HAS_DATASET=$(echo "$BINDER_JSON" | json params.delegate_dataset)
if [[ "$HAS_DATASET" != "true" ]]; then
    echo '{ "params": { "delegate_dataset": true } }' | \
        sapiadm update "$BINDER_SVC"
    [[ $? == 0 ]] || fatal "Unable to set delegate_dataset on binder service."

    # -- Verify it got there
    BINDER_JSON=$(sdc-sapi /services?name=binder\&application_uuid=$SDC_APP | \
        json -Ha)
    [[ -n "$BINDER_JSON" ]] || fatal "could not fetch sdc 'binder' BINDER service"
    HAS_DATASET=$(echo "$BINDER_JSON" | json params.delegate_dataset)
    [[ "$HAS_DATASET" == "true" ]] || \
        fatal "sapiadm updated the binder service but it didn't take"
fi

# -- Add a delegated dataset to current binder, if needed (more MANTA-2297).
DATASET="zones/$CUR_UUID/data"
VMAPI_DATASET=$(sdc-vmapi /vms/$CUR_UUID | json -Ha datasets.0)
if [[ "$DATASET" != "$VMAPI_DATASET" ]]; then
    zfs list "$DATASET" && rc=$? || rc=$?
    if [[ $rc != 0 ]]; then
        zfs create $DATASET
        [[ $? == 0 ]] || fatal "Unable to create binder zfs dataset"
    fi

    zfs set zoned=on $DATASET
    [[ $? == 0 ]] || fatal "Unable to set zoned=on on binder dataset"

    zonecfg -z $CUR_UUID "add dataset; set name=${DATASET}; end"
    [[ $? == 0 ]] || fatal "Unable to set dataset on binder zone"

    VMADM_DATASET=$(vmadm get $CUR_UUID | json datasets.0)
    [[ "$DATASET" == "$VMADM_DATASET" ]] || \
        fatal "Set dataset on binder zone, but getting did not work"

    # Reboot to make the delegated dataset appear in the zone.
    vmadm reboot $CUR_UUID
fi


# -- Get the new image.
./download-image.sh ${BINDER_IMAGE}
[[ $? == 0 ]] || fatal "Unable to download/install binder image $BINDER_IMAGE"

# -- Update service data in BINDER.
update_svc_user_script $CUR_UUID $BINDER_IMAGE
sapiadm update $BINDER_SVC params.image_uuid=$BINDER_IMAGE

# -- Upgrade zone.

# Move the zk db to the delegated dataset (if we need to, more MANTA-2297)
if [[ -e /zones/$CUR_UUID/root/var/db/zookeeper/myid ]]; then
    zlogin $CUR_UUID "svcadm disable -s zookeeper && \
                      touch /var/db/zookeeper/.moved && \
                      cp -a /var/db/zookeeper /$DATASET/. && \
                      svcadm enable -s zookeeper"
fi

sapiadm reprovision $CUR_UUID $BINDER_IMAGE

echo "Done binder upgrade."
