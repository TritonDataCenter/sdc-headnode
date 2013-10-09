#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#


LOG_FILENAME=/tmp/manatee-upgrade.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin

set -o errexit
set -o xtrace

function fatal
{
    echo "FATAL: $*" >&2
    exit 2
}

function find_manatee_service_uuid
{
    manatee_svc_uuid=$(sdc-sapi /services?name=manatee | json -Ha uuid)
    if [[ -z ${manatee_svc_uuid} ]]; then
        echo ""
        fatal "unable to get manatee service uuid from SAPI."
    fi
    echo "Manatee service_uuid is ${manatee_svc_uuid}"
}

function find_manatee_instance_uuid
{
    manatee_instance=$(sdc-sapi /instances?service_uuid=${manatee_svc_uuid} | json -Ha uuid)
    if [[ -z ${manatee_instance} ]]; then
        echo ""
        fatal "unable to get manatee instance uuid from SAPI"
    fi
    echo "Manatee instance is ${manatee_instance}"
}

function disable_manatee_services
{
    echo "Bringing down manatee services"
    svcadm -z ${manatee_instance} disable -s manatee-sitter
    svcadm -z ${manatee_instance} disable -s manatee-backupserver
    svcadm -z ${manatee_instance} disable -s manatee-snapshotter
}

function enable_manatee_services
{
    echo "Bringing up manatee services"
    svcadm -z ${manatee_instance} enable -s manatee-sitter
    svcadm -z ${manatee_instance} enable -s manatee-backupserver
    svcadm -z ${manatee_instance} enable -s manatee-snapshotter
    echo "Restarting config-agent"
    svcadm -z ${manatee_instance} restart config-agent
}

function ping_postgres
{
    vm_uuid=$1

    zlogin ${vm_uuid} '/opt/local/bin/psql -U postgres -t -A \
        -c "SELECT NOW() AS when;"' >&4 2>&1

    return $?
}

function wait_for_db
{
    local instance=$1

    echo -n "Waiting for DB on ${instance} .."
    set +o errexit
    local tries=0
    while ! ping_postgres "${instance}"; do
        echo -n "."
        if [[ ${tries} -ge 36 ]]; then
            echo " FAIL"
            fatal "timed out waiting for postgres"
        fi
        sleep 5
        tries=$((${tries} + 1))
    done
    set -o errexit

    echo " It's UP!"
}

# assumes single-node mode (i.e., repl is empty)
function manatee_status
{
    status=$(zlogin ${manatee_instance} "source ~/.bashrc; manatee-stat | json sdc.primary.repl")
    if [[ -z ${status} ]]; then
        echo ""
        fatal "Unable to determine manatee status"
    fi
    if [[ ${status} != "{}" ]]; then
        echo ""
        fatal "Unexpected manatee status: "
    fi
}

function upgrade_code
{
    local manatee_root=/zones/${manatee_instance}/root/opt/smartdc
    mv ${manatee_root}/manatee ${manatee_root}/manatee_old.$$
    echo "Moved aside old code to /opt/smartdc/manatee_old.$$"
    tar -zxf ${tarball} -C ${manatee_root}
    echo "Installed new code"
}

function postflight_check
{
    echo "postflight smoke test"
    manatee_status=$(manatee_status)
    if [[ $? != 0 ]]; then
        echo ""
        fatal "unexpected manatee status"
    fi
    sapi_smoke_test=$(sdc-sapi /instances -f)
    if [[ $? != 0 ]]; then
        echo ""
        fatal "sdc-sapi error: ${sapi_smoke_test}"
    fi
    local test_count=$(printf "%d" $(sdc-sapi /instances | json -Ha uuid | wc -l))
    if [[ ${instance_count} != ${test_count} ]]; then
        echo ""
        fatal "Incorrect instance count. Expected ${instance_count}, got: ${test_count}"
    fi
}


# mainline
tarball=$1
if [[ -z ${tarball} ]]; then
    cat >&2 <<EOF
Usage: $0 <tarball path>
EOF
    exit 1
fi

echo "!! log file is ${LOG_FILENAME}"

instance_count=$(printf "%d" $(sdc-sapi /instances | json -Ha uuid | wc -l))
find_manatee_service_uuid
find_manatee_instance_uuid
manatee_status
disable_manatee_services
upgrade_code
enable_manatee_services
wait_for_db ${manatee_instance}
postflight_check

echo "Manatee upgraded in place!"
