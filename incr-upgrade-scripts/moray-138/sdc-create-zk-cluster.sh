#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# When SDC is initially set up, it has a single zookeeper, but
# requires a cluster of 3 or 5 (or 7, etc) for full durability.
# However, re-configuring zookeeper is difficult and error-prone;
# this script creates a new cluster from scratch.
#
# Given a list of server UUIDs (ideally distinct), it attempts to:
# - reserve a set of IPs to be used for the ZK nodes
# - create the SAPI metadata required for ZK instances to come up
#   with the correct config
# - provision the ZK instances themselves
#
# At the end of this process, you should have a new cluster of ZK
# instances, with a ZK_HA_SERVERS metadata property on the zookeeper
# service in SAPI. After validating the cluster, it can be promoted
# for use throughout the SDC install by adding that metadata to the
# sdc application in SAPI.

LOG_FILENAME=/tmp/zk-scaler.$$.log
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

CNS=$@
if [[ -z ${CNS} ]]; then
    fatal "Provide list of servers."
fi

function get_sdc_application_uuid
{
    sdc_uuid=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
    if [[ -z ${sdc_uuid} ]]; then
        fatal "Unable to get SDC application uuid."
    fi
    echo "SDC SAPI application UUID: ${sdc_uuid}"
}

function get_zk_service
{
    zk_suuid=$(sdc-sapi /"services?name=zookeeper&application_uuid=${sdc_uuid}" \
               | json -Ha uuid)

    if [[ -z ${zk_suuid} ]]; then
        fatal "zookeeper service couldn't be located (has it been added?)"
    fi
}

function get_admin_user_uuid
{
    ufds_admin_uuid=$(sdc-sapi /applications/${sdc_uuid} \
                 | json -Ha metadata.ufds_admin_uuid)
    if [[ -z ${ufds_admin_uuid} ]]; then
        fatal "Unable to find ufds_admin_uuid."
    fi
    echo "Admin user UFDS UUID: ${ufds_admin_uuid}"
}

function get_admin_net_uuid
{
    admin_net_uuid=$(sdc-napi /networks?name=admin \
                     | json -Ha uuid)
    if [[ -z ${admin_net_uuid} ]]; then
        fatal "Unable to find admin network uuid."
    fi
    echo "Admin network UUID: ${admin_net_uuid}"
}

function reserve_ip
{
    local uuid=$1
    if [[ -z $uuid ]]; then
        fatal "No UUID passed to reserve_ip()"
    fi

    local req=$(echo {} | json -o jsony-0 -e "
                owner_uuid='${ufds_admin_uuid}';
                belongs_to_uuid='${uuid}';
                belongs_to_type='zone'")

    local ip=$(sdc-napi /networks/${admin_net_uuid}/nics -X POST -f -d ${req} \
        | json -H ip)
    if [[ $? != 0 || -z ${ip} ]]; then
        fatal "Could not reserve an IP."
    fi
    echo ${ip}
}

function create_cluster_config
{
    local count=0
    local islast="true"

    if [[ -z ${server_file} ]]; then
        server_file=/var/tmp/zk-scaler-servers.$$.json
    fi
    if [[ -z ${instance_file} ]]; then
        instance_file=/var/tmp/zk-scaler-instances.$$.json
    fi

    for CN in ${CNS}; do
        local alias=zookeeper${count}
        count=$((${count} + 1))
        local myid=${count}

        local uuid=$(uuid -v4)
        local ip=$(reserve_ip ${uuid})

        # echo information to sapi instance snippets.
        echo '{"params":{}, "metadata":{}}' | json -e \
           "service_uuid='${zk_suuid}';
            params.alias='${alias}';
            uuid='${uuid}';
            params.server_uuid='${CN}';
            metadata.ZK_ID=${myid};" >> ${instance_file}

        # echo information to sapi application snippets (ZK_HA_SERVER entries).
        # prepend them to make the last thing easier.
        echo '{}' | json -e \
           "host='${ip}';
            port=2181;
            num=${myid};
            last:false;" >> ${server_file}
    done

    # done all the servers, post-process the files.
    json -gf ${instance_file} > /var/tmp/$$.json
    cp /var/tmp/$$.json ${instance_file}

    json -gf ${server_file} -Ae 'this[this.length-1].last=true' > /var/tmp/$$.json
    cp /var/tmp/$$.json ${server_file}
}

# update sapi metadata for new ZK cluster. We add a new property,
# ZK_HA_SERVERS, on the same model as the current ZK_SERVERS. At
# this point, we add it *only* to the new ZK service, so that the
# new instances will have the correct config upon standup, but
# will not impinge on existing services.
function add_zk_ha_config
{
    local zk_list=$1
    local sapi_update=/var/tmp/zk-scaler-sapi-update.$$.json
    if [[ -z ${zk_list} ]]; then
        fatal "No update file supplied"
    fi

    echo '{"metadata":{}}' | json -e "metadata.ZK_HA_SERVERS=$(json -f ${zk_list})" \
        > ${sapi_update}
    sdc-sapi /services/${zk_suuid} -f -X PUT -d @${sapi_update}
    if [[ $? != 0 ]]; then
        fatal "Couldn't update ZK_HA metadata in zookeeper service."
    fi
}

function create_cluster
{
    local instance_file=$1
    if [[ -z ${instance_file} ]]; then
        fatal "No instances supplied to provision"
    fi

    # file is an array of json objects, each of which is a provision payload.
    for payload in $(json -f ${instance_file} -o jsony-0 -a); do
        echo ${payload} | sapiadm provision
    done
}

echo "!! log file is ${LOG_FILENAME}"

# Gather uuids, etc.
get_sdc_application_uuid
get_zk_service
get_admin_user_uuid
get_admin_net_uuid

# Mainline
create_cluster_config
add_zk_ha_config ${server_file}
create_cluster ${instance_file}
