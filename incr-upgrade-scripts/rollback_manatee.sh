#!/usr/bin/bash
#
# rollback_manatee.sh
#
# XXX - currently assumes running on the same server as both
# the target instance and destination directory
#
# input - instance uuid, source for stream to restore.

# verify it's a zone.

set -o errexit
set -o xtrace
set -o pipefail

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}

UUID=$1
if [[ -z ${UUID} ]]; then
    fatal "Provide UUID"
fi

ZFS=$2
if [[ -z ${ZFS} || -z $(ls ${ZFS}) ]]; then
    fatal "Provide backup stream"
fi

XML=$3
if [[ -z ${XML} || -z $(ls ${XML}) ]]; then
    fatal "Provide zone XML"
fi


function verify_zone_uuid
{
    local worked=$(sdc-vmapi /vms/${UUID} -f | json -H uuid)
    if [[ -z ${worked} ]]; then
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

function rollback_manatee
{
    # work around OS-XXX
    umount /zones/${UUID}/cores
    umount /zones/${UUID}

    zfs destroy -r zones/${UUID}

    zfs recv -Fv zones/${UUID} < ${ZFS}
    cp ${XML} /etc/zones/${UUID}.xml
}

function restart_zone
{
    vmadm start ${UUID}
}

# Mainline


verify_zone_uuid
stop_zone
rollback_manatee
restart_zone
