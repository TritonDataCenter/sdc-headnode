#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#
# Adds a zookeeper service description to SAPI, where one doesn't already
# exist. The zookeeper service is identical to the existing 'binder' service.

LOG_FILENAME=/tmp/zk-reconfig.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin

set -o xtrace
set -o pipefail

function fatal
{
    echo "FATAL: $*" >&2
    exit 2
}

# need new manatee-stat for this stage; manatee's going to bounce around.

function find_sdc_application
{
    sdc_application=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
    if [[ -z ${sdc_application} ]]; then
        echo ""
        fatal "unable to find sdc application uuid"
    fi
    echo "SDC application uuid is ${sdc_application}"
}

function find_zookeeper_service
{
    zookeeper_svc_uuid=$(sdc-sapi /services?name=zookeeper | json -Ha uuid)
        if [[ -z ${zookeeper_svc_uuid} ]]; then
        echo ""
        fatal "unable to get zookeeper service uuid from SAPI."
    fi
    echo "zookeeper service_uuid is ${zookeeper_svc_uuid}"
}

function find_moray_service
{
    moray_svc_uuid=$(sdc-sapi /services?name=moray | json -Ha uuid)
        if [[ -z ${moray_svc_uuid} ]]; then
        echo ""
        fatal "unable to get moray service uuid from SAPI."
    fi
    echo "moray service_uuid is ${moray_svc_uuid}"
}

function find_manatee_service
{
    manatee_svc_uuid=$(sdc-sapi /services?name=manatee | json -Ha uuid)
        if [[ -z ${manatee_svc_uuid} ]]; then
        echo ""
        fatal "unable to get manatee service uuid from SAPI."
    fi
    echo "manatee service_uuid is ${manatee_svc_uuid}"
}

function find_binder_service
{
    binder_svc_uuid=$(sdc-sapi /services?name=binder | json -Ha uuid)
        if [[ -z ${binder_svc_uuid} ]]; then
        echo ""
        fatal "unable to get binder service uuid from SAPI."
    fi
    echo "binder service_uuid is ${binder_svc_uuid}"
}

function get_zk_ha_config
{
    zk_ha_config=$(sdc-sapi /services/${zookeeper_svc_uuid} \
                   | json -H metadata.ZK_HA_SERVERS)
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Couldn't get ZK ha config."
    fi
}

function find_moray_instances
{
    echo "Finding all moray instances & servers."
    moray_instances=$(sdc-vmapi '/vms?tag.smartdc_role=moray&state=running' | \
                      json -d'+' -Ha uuid server_uuid)
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Couldn't find moray instances."
    fi
}

function find_manatee_instances
{
    echo "Finding all manatee instances & servers."
    primary_manatee=$(sdc-manatee-stat | json -Ha sdc.primary.zoneId)
    if [[ -z ${primary_manatee} ]]; then
        echo ""
        fatal "Can't find primary manatee"
    fi
    primary_server=$(sdc-vmapi /vms/${primary_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${primary_server} ]]; then
        echo ""
        fatal "Can't find server for primary: ${primary_manatee}"
    fi
    sync_manatee=$(sdc-manatee-stat | json -Ha sdc.sync.zoneId)
    if [[ -z ${sync_manatee} ]]; then
        echo ""
        fatal "Can't find sync manatee"
    fi
    sync_server=$(sdc-vmapi /vms/${sync_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${sync_server} ]]; then
        echo ""
        fatal "Can't find server for sync: ${sync_manatee}"
    fi
    async_manatee=$(sdc-manatee-stat | json -Ha sdc.async.zoneId)
    if [[ -z ${async_manatee} ]]; then
        echo ""
        fatal "Can't find async manatee"
    fi
    async_server=$(sdc-vmapi /vms/${async_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${async_server} ]]; then
        echo ""
        fatal "Can't find server for async: ${async_manatee}"
    fi
}

# generally want to wait for:
#   onenode - single node primary.
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
        onenode)
            cmd='json sdc.primary.repl'
            target='{}'
            ;;
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

function disable_config_agent
{
    local server=${1:37}
    local zone=${1:0:36}
    echo "Disabling config-agent for ${zone}"
    sdc-oneachnode -n ${server} "svcadm -z ${zone} disable -s config-agent"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to disable config agents for ${zone} on server ${server}."
    fi
}

function disable_all_config_agent
{
    disable_config_agent ${primary_manatee}+${primary_server}
    disable_config_agent ${sync_manatee}+${sync_server}
    disable_config_agent ${async_manatee}+${async_server}
    for pair in ${moray_instances}; do
        disable_config_agent ${pair}
    done
}

function disable_manatee
{
    local server=$1
    local zone=$2
    echo "Disabling manatee services for ${zone}"
    sdc-oneachnode -n ${server} \
        "svcadm -z ${zone} disable -s manatee-sitter; \
         svcadm -z ${zone} disable -s manatee-backupserver; \
         svcadm -z ${zone} disable -s manatee-snapshotter;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to disable manatee services in ${zone} on ${server}"
    fi
}

function enable_manatee
{
    local server=$1
    local zone=$2
    echo "Enabling manatee services for ${zone}"
    sdc-oneachnode -n ${server} \
        "svcadm -z ${zone} enable -s manatee-sitter; \
         svcadm -z ${zone} enable -s manatee-backupserver; \
         svcadm -z ${zone} enable -s manatee-snapshotter;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to enable all manatee services in ${zone} on ${server}"
    fi
}


function disable_moray
{
    local server=${1:37}
    local zone=${1:0:36}
    echo "Disabling moray services for ${zone}"
    sdc-oneachnode -n ${server} \
        "svcadm -z ${zone} disable -s moray-2021;\
         svcadm -z ${zone} disable -s moray-2022;\
         svcadm -z ${zone} disable -s moray-2023;\
         svcadm -z ${zone} disable -s moray-2024;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to disable all moray services in ${zone} on ${server}"
    fi
}

function enable_moray
{
    local server=${1:37}
    local zone=${1:0:36}
    echo "Enabling moray services for ${zone}"
    sdc-oneachnode -n ${server} \
        "svcadm -z ${zone} enable -s moray-2021;\
         svcadm -z ${zone} enable -s moray-2022;\
         svcadm -z ${zone} enable -s moray-2023;\
         svcadm -z ${zone} enable -s moray-2024;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to enable all moray services in ${zone} on ${server}"
    fi
}

function bring_down_moray
{
    for pair in ${moray_instances}; do
        disable_moray ${pair}
    done
}

function change_binder_config
{
    echo "Preventing binder from picking up wrong ZK"
    sdc-sapi /services/${binder_svc_uuid} -X PUT -f -d '{"metadata" : {"ZK_HA_SERVERS":false} }'
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to add ZK_HA_SERVERS to binder service"
    fi
}

function promote_zk_ha
{
    echo "Writing HA ZK cluster config to sdc application metadata"
    local payload=$(echo '{"metadata":{}}' \
                    | json -e "metadata.ZK_HA_SERVERS=${zk_ha_config}" \
                    | json -o json-0)
    sdc-sapi /applications/${sdc_application} -f -X PUT -d "${payload}"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to add ZK_HA_SERVERS to application metadata"
    fi
}

function bring_up_moray
{
    for pair in ${moray_instances}; do
        enable_moray ${pair}
    done
}

function bring_down_manatee
{
    # want to go async, sync, primary.
    disable_manatee ${async_server} ${async_manatee}
    wait_for_manatee sync
    disable_manatee ${sync_server} ${sync_manatee}
    wait_for_manatee onenode
    disable_manatee ${primary_server} ${primary_manatee}
}

function bring_up_manatee
{
    # order matters - old primary first.
    enable_manatee ${primary_server} ${primary_manatee}
    wait_for_manatee onenode
    enable_manatee ${sync_server} ${sync_manatee}
    wait_for_manatee sync
    enable_manatee ${async_server} ${async_manatee}
    wait_for_manatee full
}

function write_new_manatee_config
{
    local tiny_json=$(echo ${zk_ha_config} | json -o json-0)
    local server=$1
    local zone=$2
    local local_path=/tmp/${zone}/
    local remote_path=/zones/${zone}/root/opt/smartdc/manatee/etc/

    local cfg=sitter.json
    local new=sitter.json.$$.new
    local old=sitter.json.$$.old

    echo "Fetching old config from ${zone}"
    mkdir -p ${local_path}
    sdc-oneachnode -n ${server} -p ${remote_path}/${cfg} -d ${local_path}
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to fetch ${remote_path}/${cfg} from ${server}"
    fi

    echo "Rewriting config"
    # sdc-oneachnode -p puts as $dir/$server
    json -f ${local_path}/${server} -e "zkCfg.servers=${tiny_json}" \
        > ${local_path}/${new}

    echo "Sending new config to ${zone}"
    sdc-oneachnode -n ${server} -g ${local_path}/${new} -d ${remote_path}
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to send new config to ${remote_path} on ${server}"
    fi

    sdc-oneachnode -n ${server} \
        "cp ${remote_path}/${cfg} ${remote_path}/${old};
         cp ${remote_path}/${new} ${remote_path}/${cfg}"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to overwrite old config on ${server}"
    fi
}

function write_new_manatee_configs
{
    write_new_manatee_config ${primary_server} ${primary_manatee}
    write_new_manatee_config ${sync_server} ${sync_manatee}
    write_new_manatee_config ${async_server} ${async_manatee}
}

function write_manatee_cli_config
{
    local server=$1
    local zone=$2

    sdc-oneachnode -n ${server} -g /tmp/zk_ips.sh.new \
        -d /zones/${zone}/root/opt/smartdc/etc
    sdc-oneachnode -n ${server} \
        "cp /zones/${zone}/root/opt/smartdc/etc/zk_ips.sh \
            /zones/${zone}/root/opt/smartdc/etc/zk_ips.sh.old; \
         cp /zones/${zone}/root/opt/smartdc/etc/zk_ips.sh.new \
            /zones/${zone}/root/opt/smartdc/etc/zk_ips.sh;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to write new manatee CLI zk_ips to ${server}"
    fi
}

function write_new_manatee_cli_configs
{
    echo "Writing new manatee CLI configs."

    local ips=$(echo ${zk_ha_config} | json -a host | xargs)
    echo "ZK_IPS=\"${ips}\"" > /tmp/zk_ips.sh.new

    write_manatee_cli_config ${primary_server} ${primary_manatee}
    write_manatee_cli_config ${sync_server} ${sync_manatee}
    write_manatee_cli_config ${async_server} ${async_manatee}
}

function write_new_moray_config
{
    local tiny_json=$(echo ${zk_ha_config} | json -o json-0)
    local server=$1
    local zone=$2
    local local_path=/tmp/${zone}/
    local remote_path=/zones/${zone}/root/opt/smartdc/moray/etc/

    local cfg=config.json
    local new=config.json.$$.new
    local old=config.json.$$.old

    echo "Fetching old config from ${zone}"
    mkdir -p ${local_path}
    sdc-oneachnode -n ${server} -p ${remote_path}/${cfg} -d ${local_path}
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to get old moray config from ${remote_path}/${cfg} on ${server}"
    fi

    echo "Rewriting config"
    # sdc-oneachnode -p puts as $dir/$server
    json -f ${local_path}/${server} -e "manatee.zk.servers=${tiny_json}" \
        > ${local_path}/${new}

    echo "Sending new config to ${zone}"
    sdc-oneachnode -n ${server} -g ${local_path}/${new} -d ${remote_path}
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to send new moray config to ${server}"
    fi

    sdc-oneachnode -n ${server} \
        "cp ${remote_path}/${cfg} ${remote_path}/${old};
         cp ${remote_path}/${new} ${remote_path}/${cfg}"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Unable to overwrite old moray config on ${server}"
    fi
}

function write_new_moray_configs
{
    local server=
    local zone=
    for pair in ${moray_instances}; do
        server=${pair:37}
        zone=${pair:0:36}
        write_new_moray_config ${server} ${zone}
    done
}

# mainline
echo "!! log file is ${LOG_FILENAME}"

# get all the services we need
find_sdc_application
find_zookeeper_service
find_moray_service
find_moray_instances
find_manatee_service
find_manatee_instances
find_binder_service


# get new ZK server json from zk service
get_zk_ha_config

# bring down config-agent in moray/manatee zones
disable_all_config_agent

# write ZK_HA_SERVERS=false to binder config (so it stays with local ZK).
change_binder_config

# write ZK_HA_SERVERS to sdc application (should have no effect)
promote_zk_ha

echo "Bringing down services."
bring_down_moray
bring_down_manatee

echo "Writing new configs."
write_new_manatee_configs
write_new_manatee_cli_configs
write_new_moray_configs

echo "Bringing services back up."
bring_up_manatee
bring_up_moray

echo "Done, modulus config-agents."
