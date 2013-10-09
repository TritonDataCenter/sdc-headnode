#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# Checks health of zookeeper cluster.

LOG_FILENAME=/tmp/zk-scaler-check.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin

set -o errexit
set -o xtrace
set -o pipefail

function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}

function get_zk_service_uuid
{
    zookeeper_svc_uuid=$(sdc-sapi "/services?name=zookeeper" | json -Ha uuid)
    if [[ -z ${zookeeper_svc_uuid} ]]; then
        echo ""
        fatal "unable to get zookeeper service uuid from sapi."
    fi
    echo "Zookeeper service_uuid is ${zookeeper_svc_uuid}"
}

function get_zk_instances
{
    zookeeper_instances=$(sdc-sapi /instances?service_uuid=${zookeeper_svc_uuid} | json -Ha uuid | xargs)
    if [[ -z ${zookeeper_instances} ]]; then
        echo ""
        fatal "unable to find zookeeper instances"
    fi
}

function get_zk_ip
{
    local uuid=$1
    local ip=$(sdc-vmapi /vms/${uuid} | json -Ha nics[0].ip)
}

function check_instance
{
    local uuid=$1
    local ip=$(sdc-vmapi /vms/${uuid} -f | json -Ha nics[0].ip)
    local isok=$(echo ruok | nc ${ip} 2181)
    local mntr=$(echo mntr | nc ${ip} 2181)
    local stat=$(echo stat | nc ${ip} 2181)
    # determine leader from that, otherwise just echo stats.
    echo "${uuid} at ${ip} reports: ${isok}"
}

# function check_sync
# {
#     for uuid in ${zookeeper_instances}; do
#         leader=
#     done
# }

function check_zk
{
    local ok
    local ip
    for uuid in ${zookeeper_instances}; do
        ok=$(check_instance ${uuid})
        echo ${ok}
    done
}

echo "!! log file is ${LOG_FILENAME}"

# mainline
get_zk_service_uuid
get_zk_instances
check_zk
