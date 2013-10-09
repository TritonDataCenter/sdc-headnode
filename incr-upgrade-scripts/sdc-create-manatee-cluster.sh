#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#


LOG_FILENAME=/tmp/manatee-cluster.$$.log
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

# find sapi
function find_sdc_application_uuid
{
    sdc_uuid=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
    if [[ -z ${sdc_uuid} ]]; then
        fatal "Unable to get SDC application uuid."
    fi
    echo "SDC SAPI application UUID: ${sdc_uuid}"
}

function find_sapi_service_uuid
{
    sapi_svc_uuid=$(sdc-sapi "/services?name=sapi&application_uuid=${sdc_uuid}" | json -Ha uuid)
    if [[ -z ${zookeeper_svc_uuid} ]]; then
        echo ""
        fatal "unable to get sapi service uuid from SAPI."
    fi
    echo "Manatee service_uuid is ${manatee_svc_uuid}"
}

function find_sapi_instance_uuid
{
    sapi_instance=$(sdc-sapi /instances?service_uuid=${sapi_svc_uuid} | json -Ha uuid)
    if [[ -z ${sapi_instance} ]]; then
        echo ""
        fatal "unable to get sapi instance uuid from SAPI"
    fi
    echo "sapi instance is ${sapi_instance}"
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

# update sapi with new image uuid
function update_sapi
{
    sdc-sapi /instances/${manatee_svc_uuid} -X PUT -d "{ \
        \"params\" : { \"image_uuid\" : \"${manatee_image_uuid}\" } \
    }" -f
}

# mainline
manatee_image_uuid=$1
if [[ -z ${manatee_image_uuid} ]]; then
    cat >&2 <<EOF
Usage: $0 <manatee_image> <server_uuid1> <server_uuid2>
EOF
    exit 1
fi

manatee_server_2=$2
if [[ -z ${manatee_server_2} ]]; then
    cat >&2 <<EOF
Usage: $0 <manatee_image> <server_uuid1> <server_uuid2>
EOF
    exit 1
fi

manatee_server_3=$3
if [[ -z ${manatee_server_3} ]]; then
    cat >&2 <<EOF
Usage: $0 <manatee_image> <server_uuid1> <server_uuid2>
EOF
    exit 1
fi

find_sdc_application_uuid
find_sapi_service_uuid
find_sapi_instance_uuid
find_manatee_service_uuid
update_sapi

# create number 2!
sdc-create-2nd-manatee ${manatee_server_2}

# create number 3!
echo "Provisioning third manatee"
echo '{"params":{}}' | json -e "params.alias='manatee2'; " | sapiadm provision ${manatee_svc_uuid}
