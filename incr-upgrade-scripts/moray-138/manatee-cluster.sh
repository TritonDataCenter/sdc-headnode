#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#


LOG_FILENAME=/tmp/manatee-cluster.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin:$PATH

set -o errexit
set -o xtrace
set -o pipefail

function fatal
{
    echo "FATAL: $*" >&2
    exit 2
}

function wait_for_ops
{
    local msg=$1
    if [[ -z ${msg} ]]; then
        msg="Script paused. Enter to continue, ^C to end here."
    fi
    echo ${msg}
    read foo
}

# generally want to wait for:
#   sync - stable primary/sync two-node config.
#   full - stable primary/sync/async config.
function wait_for_manatee
{
    local wait_for=$1
    local cmd=
    local target=
    local result=
    local count=0
    case "${wait_for}" in
        sync)
            cmd='json sdc.primary.repl.sync_state'
            target='sync'
            ;;
        full)
            cmd='json sdc.sync.repl.sync_state'
            target='async'
            ;;
        *)
            echo ""
            fatal "asked to wait for nonsense state ${wait_for}"
            ;;
    esac
    echo "Waiting for manatee to reach ${wait_for} state (max 120s)"
    while [[ ${result} != ${target} ]]; do
        result=$(sdc-manatee-stat | ${cmd})
        echo -n "."
        if [[ ${result} != ${target} ]]; then
            continue;
        elif [[ ${count} -gt 12 ]]; then
            fatal "Timeout waiting (120s) for manatee to reach ${wait_for}"
        else
            count=$((${count} + 1))
            sleep 5
        fi
    done
    echo "Done! Manatee reached ${wait_for}"
}

function find_manatee
{
    echo "Checking initial manatee status"
    local manatees=$('sdc-vmapi /vms?tag.smartdc_role=manatee&state=running' | json -Ha uuid | wc -l | xargs)
    if [[ ${manatees} != 1 ]]; then
        echo ""
        fatal "Expected one manatee, found: ${manatees}"
    fi
    manatee_instance=$(sdc-vmapi '/vms?tag.smartdc_role=manatee&state=running' | json -Ha uuid)
    manatee_service=$(sdc-sapi /services?name=manatee | json -Ha uuid)
    manatee_up=$(sdc-manatee-stat | json sdc.primary.repl)
    if [[ ${manatee_up} != '{}' ]]; then
        fatal "Manatee doesn't seem to be up: ${manatee_up}"
    fi
}

function find_moray
{
    moray=$(sdc-vmapi '/vms?tag.smartdc_role=moray&state=running' | json -Ha uuid | tail -1)
    if [[ -z ${moray} ]]; then
        echo ""
        fatal "Can't locate moray service."
    fi
    moray_server=$(sdc-vmapi /vms/${moray} | json -Ha server_uuid)
    if [[ -z ${moray_server} ]]; then
        echo ""
        fatal "Can't locate moray server."
    fi
    echo "Found moray."
}

function bounce_moray
{
    echo "bouncing moray services."
    sdc-oneachnode -n ${moray_server} \
    "svcadm -z ${moray} restart moray-2021;\
     svcadm -z ${moray} restart moray-2022;\
     svcadm -z ${moray} restart moray-2023;\
     svcadm -z ${moray} restart moray-2024;"
}


function check_sapi
{
    echo "Checking sapi manatee service configuration"
    local current_image=$(sdc-vmapi /vms/${manatee_instance} -f | json -Ha image_uuid)
    local sapi_image=$(sdc-sapi /services/${manatee_service} -f | json -Ha params.image_uuid)

    if [[ ${sapi_image} != ${current_image} ]]; then
        echo "Updating sapi to current manatee image"
        sdc-sapi /services/${manatee_service} -f -X PUT -d "{
            \"params\" : { \"image_uuid\" : \"${current_image}\"}
        }" >&4
    fi
}

# mainline

# beta-4 00000000-0000-0000-0000-00259094373c
#        00000000-0000-0000-0000-00259094356c
# west-x 00000000-0000-0000-0000-002590c09348
#        00000000-0000-0000-0000-002590c09440
# coal   sysinfo | json UUID

echo "!! log file is ${LOG_FILENAME}"

manatee_server_2=$1
if [[ -z ${manatee_server_2} ]]; then
    cat >&2 <<EOF
Usage: $0 <server_uuid1> <server_uuid2>
EOF
    exit 1
fi

manatee_server_3=$2
if [[ -z ${manatee_server_3} ]]; then
    cat >&2 <<EOF
Usage: $0 <server_uuid1> <server_uuid2>
EOF
    exit 1
fi

find_manatee
find_moray
check_sapi


echo "Creating second manatee instance"
sdc-create-2nd-manatee ${manatee_server_2}
# wait should be built in?

# wait for moray.
echo "Sleeping to let moray notice the manatee change."
bounce_moray
wait_for_ops "Check vmapi (ZAPI-434). [enter] to continue."

# might need to bounce vmapi, cnapi if they don't manage to reconnect.
manatee_payload=/tmp/manatee2_payload.$$.json
echo '{"params":{}}' | json -e "this.params.server_uuid='${manatee_server_3}'; \
                                this.params.alias='manatee2'; \
                                this.service_uuid='${manatee_service}'" \
                     > ${manatee_payload}
echo "Creating third manatee instance."
sdc-sapi /instances -f -X POST -d@${manatee_payload} >&4

# XXX - switch to non-errexit, because might fail here if it picks the
# wrong manatee to check. But in this situation, that's often fine, we
# can poll sdc-manatee-stat manually to watch.
# TODO: ticket on sdc-manatee-stat to sdc zone, fixed for multiple instances.
# workaround possible here by picking a UUID for the new zone that lists
# after the existing two.
wait_for_manatee full
echo "Manatee shard successfully deployed!"

