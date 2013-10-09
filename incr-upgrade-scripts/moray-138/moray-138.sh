#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#


LOG_FILENAME=/tmp/moray-138.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin

# set -o errexit
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

function check_var
{
    local var=$1
    if [[ -z ${!var} ]]; then
        echo "Config missing ${var}."
        EXIT_NOW=true
    fi
}

function parse_config
{
    manatee_image=$(json -f ${config} manatee.image)
    check_var manatee_image
    manatee_server2=$(json -f ${config} manatee.servers[0])
    check_var manatee_server2
    manatee_server3=$(json -f ${config} manatee.servers[1])
    check_var manatee_server3
    zk_service_file=$(json -f ${config} zk.service_file)
    check_var zk_service_file
    zk_image=$(json -f ${config} zk.image)
    check_var zk_image
    zk_server1=$(json -f ${config} zk.servers[0])
    check_var zk_server1
    zk_server2=$(json -f ${config} zk.servers[1])
    check_var zk_server2
    zk_server3=$(json -f ${config} zk.servers[2])
    check_var zk_server3
    if [[ -n ${EXIT_NOW} ]]; then
        echo ""
        fatal "Config incomplete, aborting."
    fi
}

echo "!! log file is ${LOG_FILENAME}"

config=$1
if [[ -z ${config} ]]; then
    cat >&2 <<EOF
Usage: $0 <config_file>
EOF
    exit 1
fi

# mainline

parse_config

echo "This script will upgrade the SDC install to fully redundant zookeeper"
echo "and manatee services, and perform the requisite reconfiguration. It"
echo "proceeds in several steps with a pause between each:"
echo "  1. making manatee redundant"
echo "  2. upgrading manatee to a recent image"
echo "  3. installing zookeeper SAPI service"
echo "  4. provisioning a new zookeeper cluster"
echo "  5. reconfiguring moray and manatee to use the new ZK cluster."
echo ""
wait_for_ops "[enter] to continue"

./manatee-cluster.sh ${manatee_server2} ${manatee_server3}
wait_for_ops
./sdc-upgrade-manatee.sh ${manatee_image}
wait_for_ops
./add-zk.sh ${zk_service_file} ${zk_image}
wait_for_ops
./sdc-create-zk-cluster.sh ${zk_server1} ${zk_server2} ${zk_server3}
wait_for_ops
./reconfig-zk.sh

echo "complete."
