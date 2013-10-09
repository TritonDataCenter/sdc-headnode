#!/usr/bin/bash
#
# sdc-zk-ha.sh: add binder instances to SDC.
#
# input - list of server UUIDs

set -o errexit
set -o xtrace
set -o pipefail

# PATH=/opt/smartdc/bin:$PATH

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

function get_binder_service_uuid
{
    binder_suuid=$(sdc-sapi "/services?name=binder&application_uuid=${sdc_uuid}" \
                   | json -Ha uuid)
    if [[ -z ${binder_suuid} ]]; then
        fatal "Unable to get binder service uuid."
    fi
    echo "binder SAPI service UUID: ${binder_suuid}"
}

function get_moray_service_uuid
{
    moray_suuid=$(sdc-sapi "/services?name=moray&application_uuid=${sdc_uuid}" \
                   | json -Ha uuid)
    if [[ -z ${moray_suuid} ]]; then
        fatal "Unable to get moray service uuid."
    fi
    echo "moray SAPI service UUID: ${moray_suuid}"
}

function get_manatee_service_uuid
{
    manatee_suuid=$(sdc-sapi "/services?name=manatee&application_uuid=${sdc_uuid}" \
                   | json -Ha uuid)
    if [[ -z ${manatee_suuid} ]]; then
        fatal "Unable to get manatee service uuid."
    fi
    echo "manatee SAPI service UUID: ${manatee_suuid}"
}

function get_manatee_instance_uuids
{
    manatee_insts=$(sdc-sapi /instances?service_uuid=${manatee_suuid} \
                    | json -Ha uuid)
    if [[ -z ${manatee_insts} ]]; then
        fatal "Unable to find any manatee instances."
    fi
    echo "SAPI manatee instance UUID(s): ${manatee_insts}"
}

function get_moray_instance_uuids
{
    moray_insts=$(sdc-sapi /instances?service_uuid=${moray_suuid} \
                  | json -Ha uuid)
    if [[ -z ${moray_insts} ]]; then
        fatal "Unable to find any moray instances."
    fi
    echo "SAPI moray instance UUID(s): ${moray_insts}"
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

function create_zk_service
{
    zk_suuid=$(sdc-sapi /"services?name=zookeeper&application_uuid=${sdc_uuid}" \
               | json -Ha uuid)

    if [[ -z ${zk_suuid} ]]; then
        echo "Creating zookeeper service entry."
        sdc-sapi /services/${binder_suuid} | json -He \
            "name='zookeeper'; uuid=undefined;
             metadata.SERVICE_NAME='zookeeper';
             metadata.SERVICE_DOMAIN='zookeeper.${sdc_domain}';
             params.tags.smartdc_role='zookeeper'" \
             > /var/tmp/zookeeper_svc.$$.json
        sdc-sapi /services -f -X POST -d @/var/tmp/zookeeper_svc.$$.json | json -H > /var/tmp/zk_svc_result.$$.json
        if [[ $? != 0 ]]; then
            fatal "Could not create Zookeeper service."
        else
            zk_suuid=$(json -f /var/tmp/zk_svc_result.$$.json uuid)
        fi
    else
        echo "ZK service already exists at ${zk_suuid}, skipping creation."
    fi
}

function create_cluster_config
{
    local CNS=$@
    if [[ -z ${CNS} ]]; then
        fatal "No servers provided for ZK cluster."
    fi
    # get current alias number as starting point.

    local count=0
    local islast="true"

    if [[ -z ${server_file} ]]; then
        server_file=/var/tmp/138-servers.$$.json
    fi
    if [[ -z ${instance_file} ]]; then
        instance_file=/var/tmp/138-instances.$$.json
    fi

    for CN in ${CNS}; do
        local alias=zk${count}
        count=$((${count} + 1))
        local myid=${count}

        local uuid=$(uuid -v4)
        local ip=$(reserve_ip ${uuid})

        # echo information to sapi instance snippets.
        echo '{"params":{}, "metadata":{}}' | json -e \
           "service_uuid='${zk_suuid}';
            params.alias='${alias}';
            uuid='${uuid}';
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
unction add_zk_ha_config
{
    local zk_list=$1
    local sapi_update=/var/tmp/sapi_zk_ha_update.$$.json
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

# add removes ZK_HA_SERVERS from binder service, preventing it from hitting
# them.
# shifts ZK_HA_SERVERS to the top level, triggering manatee & moray to
# swap to using them.
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

# Mainline
# temp - servers are three new guys on the headnode.
CONFIG=$1
if [[ -z ${CONFIG} ]]; then
    fatal "Provide config file."
fi

# gather required UUIDs, etc.
get_sdc_application_uuid
get_sdc_domain
get_binder_service_uuid
# get_moray_service_uuid
# get_manatee_service_uuid
get_admin_user_uuid
get_admin_net_uuid

# backup manatee (separate file).

# create new service.
create_zk_service

# create required config.
create_cluster_config $(json -af ${CONFIG})

# update sapi metadata for new ZK cluster. We add a new property,
# ZK_HA_SERVERS, on the same model as the current ZK_SERVERS. At
# this point, we add it *only* to the new ZK service, so that the
# new instances will have the correct config upon standup, but
# will not impinge on existing services.
add_zk_ha_config ${server_file}

# provision new instances of zookeeper
create_cluster ${instance_file}

# did it work? should this go in another file?
sleep 120

# update sapi, second phase.
# ZK_HA_SERVERS=false in binder service, to preserve it as an
#   independent ZK cluser.
# ZK_HA_SERVERS gets promoted to sapi sdc application metadata,
#   which will be picked up by manatee and moray, causing them
#   to restart
# For consistency, we delete the now-redundany ZK_HA_SERVERS from
#   zookeeper service.
promote_zk_ha_config

exit 0
