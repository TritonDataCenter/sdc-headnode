#!/usr/bin/bash

PATH=/usr/bin:/usr/sbin
export PATH

if [[ $# != 2 ]]; then
    echo "Usage: $0 <zone_name> <target_directory>"
    exit 1
fi

ZONE=$1
TARGET_DIR=$2
ROLE="amonredis"

# Don't want redis running while swapping its data.
svcadm disable redis

# Destroy previous data dataset.
DATA_DATASET=$(zfs list -H -o name|grep "${ZONE}/data$")
if [[ -z "${DATA_DATASET}" ]]; then
    echo "FATAL: Missing '${DATA_DATASET}' dataset"
    exit 105
fi
echo "==> Destroying dataset '${DATA_DATASET}'"
zfs destroy -r "${DATA_DATASET}"
if [[ $? -gt 0 ]]; then
    echo "FATAL: Unable to zfs destroy '${DATA_DATASET}' dataset"
    exit 106
fi

echo "==> Receiving '${TARGET_DIR}/${ROLE}/${ROLE}-data.zfs'"
zfs receive -v "${DATA_DATASET}" < "${TARGET_DIR}/${ROLE}/${ROLE}-data.zfs"
if [[ $? -gt 0 ]]; then
    echo "FATAL: Unable to zfs receive data dataset"
    exit 108
fi

svcadm enable redis


# Reboot the zone to set mountpoint for the new dataset properly. Then
# double check.
echo "==> Booting '${ZONE}' zone"
/usr/sbin/zoneadm -z ${ZONE} boot
if [[ "$(zfs get -H -o value mountpoint ${DATA_DATASET})" != "/data" ]]; then
    echo "==> Setting mountpoint for dataset '${DATA_DATASET}'"
    zlogin ${ZONE} /usr/sbin/zfs set mountpoint=/data "${DATA_DATASET}"
    if [[ $? -gt 0 ]]; then
        echo "FATAL: Unable to set mountpoint for data dataset into '${ZONE}' zone"
        exit 112
    fi
fi
echo "==> Waiting for 10 seconds while the zone services are running"
sleep 10


echo "==> Halting '${ZONE}' zone"
/usr/sbin/zoneadm -z ${ZONE} halt

exit 0
