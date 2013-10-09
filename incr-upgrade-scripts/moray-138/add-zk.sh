#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# Adds a zookeeper service description to SAPI, where one doesn't already
# exist. The zookeeper service is identical to the existing 'binder' service.

LOG_FILENAME=/tmp/add-zk-service.$$.log
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

function get_sdc_application_uuid
{
    sdc_uuid=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
    if [[ -z ${sdc_uuid} ]]; then
        fatal "Unable to get SDC application uuid."
    fi
    echo "SDC SAPI application UUID: ${sdc_uuid}"
}

function get_sdc_domain
{
    local dc_name=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name)
    local dns_domain=$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)
    if [[ -z ${dc_name} || -z ${dns_domain} ]]; then
        fatal "Unable to determine SDC dns names"
    fi
    sdc_domain=${dc_name}.${dns_domain}
    echo "SDC dns: ${sdc_domain}"
}

function add_image
{
    local image=$1
    local exists=$(sdc-imgapi /images/${image} | json -H uuid)
    if [[ -z ${exists} ]]; then
        echo "Fetching image ${image} from updates.joyent.com"
        sdc-imgadm import ${image} -S https://updates.joyent.com --skip-owner-check
    fi
}

# function get_binder_service_uuid
# {
#     binder_suuid=$(sdc-sapi "/services?name=binder&application_uuid=${sdc_uuid}" \
#                    | json -Ha uuid)
#     if [[ -z ${binder_suuid} ]]; then
#         fatal "Unable to get binder service uuid."
#     fi
#     echo "binder SAPI service UUID: ${binder_suuid}"
# }

function create_zk_service
{
    local svc_file=$1

    local zk_suuid=$(sdc-sapi /"services?name=zookeeper&application_uuid=${sdc_uuid}" \
               | json -Ha uuid)

    if [[ -z ${zk_suui} ]]; then
        echo "Creating zookeeper SAPI service"
        local billing_id=$(sdc-sapi /services?name=binder | json -Ha params.billing_id)
        local sapi_url=$(sdc-sapi /services?name=binder | json -Ha 'metadata["sapi-url"]')
        local assets_ip=$(sdc-sapi /services?name=binder | json -Ha 'metadata["assets-ip"]')
        local svc_domain=zookeeper.${sdc_domain}
        local tmp_zk_file=/var/tmp/zk_service.$$.json

        json -f ${svc_file} \
            | json -e "application_uuid='${sdc_uuid}'" \
            | json -e "params.image_uuid='${zookeeper_image}'" \
            | json -e "params.billing_id='${billing_id}'" \
            | json -e "metadata['sapi-url']='${sapi_url}'" \
            | json -e "metadata['assets-ip']='${assets_ip}'" \
            | json -e "metadata.SERVICE_DOMAIN='${svc_domain}'" \
            > ${tmp_zk_file}

        zk_uuid=$(sdc-sapi /services -X POST -f -d@${tmp_zk_file} | json -H uuid)
        echo "zookeeper SAPI service is ${zk_uuid}"
    else
        echo "zookeeper SAPI service exists at ${zk_suuid}, skipping creation"
    fi
}

function update_sdc_app
{
    local sdc_update=/var/tmp/sdc_update.$$.json
    echo '{"metadata":{}}' \
        | json -e "metadata.ZOOKEEPER_SERVICE='zookeeper.${sdc_domain}'" \
        | json -e "metadata.sdc_domain='zookeeper.${sdc_domain}'" \
        > ${sdc_update}

    sdc-sapi /applications/${sdc_uuid} -X PUT -f -d@${sdc_update}
}

# function create_zk_service
# {
#     zk_suuid=$(sdc-sapi /"services?name=zookeeper&application_uuid=${sdc_uuid}" \
#                | json -Ha uuid)

#     if [[ -z ${zk_suuid} ]]; then
#         echo "Creating zookeeper service entry."
#         sdc-sapi /services/${binder_suuid} | json -He \
#             "name='zookeeper'; uuid=undefined;
#              metadata.SERVICE_NAME='zookeeper';
#              metadata.SERVICE_DOMAIN='zookeeper.${sdc_domain}';
#              params.tags.smartdc_role='zookeeper'" \
#              > /var/tmp/zookeeper_svc.$$.json
#         sdc-sapi /services -f -X POST -d @/var/tmp/zookeeper_svc.$$.json | json -H > /var/tmp/zk_svc_result.$$.json
#         if [[ $? != 0 ]]; then
#             fatal "Could not create Zookeeper service."
#         else
#             zk_suuid=$(json -Hf /var/tmp/zk_svc_result.$$.json uuid)
#             echo "Created ZK service at ${zk_suuid}"
#         fi
#     else
#         echo "ZK service already exists at ${zk_suuid}, skipping creation."
#         exit 0
#     fi
# }


zookeeper_svc_file=$1
if [[ -z ${zookeeper_svc_file} ]]; then
    cat >&2 <<EOF
Usage: $0 <zookeeper_file> <zookeeper_image>
EOF
    exit 1
fi

zookeeper_image=$2
if [[ -z ${zookeeper_image} ]]; then
    cat >&2 <<EOF
Usage: $0 <zookeeper_file> <zookeeper_image>
EOF
    exit 1
fi

echo "!! log file is ${LOG_FILENAME}"

# Mainline

get_sdc_application_uuid
get_sdc_domain
add_image ${zookeeper_image}
# get_binder_service_uuid
create_zk_service ${zookeeper_svc_file} ${zookeeper_image}
