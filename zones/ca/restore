#!/usr/bin/bash

PATH=/usr/bin:/usr/sbin
export PATH

if [[ $# != 2 ]]; then
  echo "Usage: $0 <zone_name> <target_directory>"
  exit 1
fi

ZONE=$1
TARGET_DIR=$2
ROLE="ca"

# We want to disable any of the old smartdc svcs to prevent the SMF repository
# from being out of sync with the restored zone data.
# The zone is halted when we start restoring so use svc to talk to the zone's
# repo.
echo "==> Disabling 'smartdc' services on zone '${ZONE}'"
export SVCCFG_CHECKHASH=1
export SVCCFG_REPOSITORY=/zones/${ZONE}/root/etc/svc/repository.db
for service in `svccfg list | egrep smartdc`
do
	if [[ $service != "system/filesystem/smartdc" && \
	    $service != "platform/smartdc/capi_ipf_setup" ]]; then

		svccfg -s "$service:default" setprop general/enabled=false \
		    >/dev/null 2>&1
	fi
done
unset SVCCFG_CHECKHASH
unset SVCCFG_REPOSITORY

# We're gonna check for existing zone datasets.
# If they're there, we'll remove them.
DATA_DATASET=$(zfs list -H -o name|grep "${ZONE}/data$")

# Destroy previous dataset.
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

# ZFS receive the dataset from the backup:
echo "==> Receiving '${TARGET_DIR}/${ROLE}/ca-data.zfs'"
zfs receive -v "${DATA_DATASET}" < "${TARGET_DIR}/${ROLE}/ca-data.zfs"
if [[ $? -gt 0 ]]; then
    echo "FATAL: Unable to zfs receive data dataset"
    exit 108
  fi

# Now we need to reboot the zone in order to be able to set mountpoint for the
# new dataset properly:

echo "==> Booting '${ZONE}' zone"
/usr/sbin/zoneadm -z ${ZONE} boot

# Double check mountpoint for backup dataset:
if [[ "$(zfs get -H -o value mountpoint ${DATA_DATASET})" != "/var/smartdc/${ROLE}"  ]]; then
    echo "==> Setting mountpoint for dataset '${DATA_DATASET}'"
    zlogin ${ZONE} /usr/sbin/zfs set mountpoint=/var/smartdc/${ROLE} \
       "${DATA_DATASET}"
    if [[ $? -gt 0 ]]; then
        echo "FATAL: Unable to set mountpoint for data dataset into '${ZONE}' zone"
        exit 112
    fi
fi

echo "==> Waiting for 10 seconds while the zone services are running ..."
sleep 10

echo "==> Enabling 'smartdc' services on zone '${ZONE}' and waiting for 5 seconds"

services=$(/usr/sbin/zlogin ${ZONE} /usr/bin/svcs -a -o FMRI|grep smartdc)
for service in $services; do
  if [[ $service != 'svc:/system/filesystem/smartdc:default' ]]; then
    $(/usr/sbin/zlogin ${ZONE} /usr/sbin/svcadm enable "$service")
  fi
done

sleep 5

echo "==> Halting '${ZONE}' zone"
/usr/sbin/zoneadm -z ${ZONE} halt

echo "==> All done!!!"

exit 0
