#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# Used during upgrade of SDC to using a fully-redundant ZK setup; the cluster
# needs to be 'promoted' to sdc-level application metadata in order to be
# picked up by moray/manatee.
#
# We do this by defining ZK_HA_SERVERS at the application level, which will
# be used by moray and manatee. We set ZK_HA_SERVERS=false to prevent it from
# being used for binder.

LOG_FILENAME=/tmp/zk-scaler-promotion.$$.log
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

function get_binder_service_uuid
{
    binder_suuid=$(sdc-sapi "/services?name=binder&application_uuid=${sdc_uuid}" \
                   | json -Ha uuid)
    if [[ -z ${binder_suuid} ]]; then
        fatal "Unable to get binder service uuid."
    fi
    echo "binder SAPI service UUID: ${binder_suuid}"
}

function get_zk_service
{
    zk_suuid=$(sdc-sapi /"services?name=zookeeper&application_uuid=${sdc_uuid}" \
               | json -Ha uuid)

    if [[ -z ${zk_suuid} ]]; then
        fatal "zookeeper service couldn't be located (has it been added?)"
    fi
}

function promote_zk_ha_config
{
    echo '{"metadata":{}}' | json -e "metadata.ZK_HA_SERVERS=false" \
        | sapiadm update ${binder_suuid}

    local zk_ha_servers=$(sapiadm get ${zk_suuid} \
                          | json -o jsony-0 metadata.ZK_HA_SERVERS)
    echo '{"metadata":{}}' | json -e "metadata.ZK_HA_SERVERS=${zk_ha_servers}" \
        | sapiadm update ${sdc_uuid}
    echo '{"metadata":{"ZK_HA_SERVERS":[]}, "action":"delete"}' \
        | sapiadm update ${zk_suuid}
}

# Gather UUIDs, etc
get_sdc_application_uuid
get_binder_service_uuid
get_zk_service

# Mainline
promote_zk_ha_config
