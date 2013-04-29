#!/usr/bin/bash

PATH=/usr/bin:/usr/sbin
export PATH

if [[ $# != 2 ]]; then
    echo "Usage: $0 <zone_name> <target_directory>"
    exit 1
fi

ZONE=$1
TARGET_DIR=$2
ROLE="imgapi"

# Don't want imgapi running while swapping its data.
svcadm disable imgapi

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

svcadm enable imgapi

echo "==> Halting '${ZONE}' zone"
/usr/sbin/zoneadm -z ${ZONE} halt

exit 0
