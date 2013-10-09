#!/usr/bin/bash
#
# backup_manatee.sh
#
# XXX - currently assumes running on the same server as both
# the target instance and destination directory.
#
# input - instance UUID, destination for stream,
#         (optional) suffix for backup.

set -o errexit
set -o xtrace
set -o pipefail

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}

UUID=$1
if [[ -z ${UUID} ]]; then
    fatal "Provide zone UUID"
fi

DEST=$2
if [[ -z ${DEST} ]]; then
    fatal "Provide destination"
fi

SUFFIX=$3
if [[ -z ${SUFFIX} ]]; then
    SUFFIX=backup-$$
    echo "No backup suffix provided, using ${SUFFIX}"
fi

# verify it's a zone.
function verify_zone_uuid
{
    local worked=$(sdc-vmapi /vms/${UUID} -f | json -H uuid)
    if [[ $? != 0 || -z ${worked} ]]; then
        fatal "${UUID} doesn't appear to be a zone?"
    fi
}

# shut it down
function stop_zone
{
    # XXX - With a single manatee instance, we will race
    # (and probably lose) on manatee stop via vmapi/workflow.
    vmadm stop ${UUID}
}

function backup_zone
{
    zfs snapshot -r zones/${UUID}@${SUFFIX}
    # confirm
    zfs list -t snapshot | grep ${SUFFIX}

    # XXX - Josh suggests clone might be faster on recovery.
    zfs send -R zones/${UUID}@${SUFFIX} > ${DEST}/${UUID}@${SUFFIX}.zfs
    cp /etc/zones/${UUID}.xml ${DEST}/${UUID}@${SUFFIX}.xml
}

# Mainline

verify_zone_uuid
stop_zone
backup_zone




