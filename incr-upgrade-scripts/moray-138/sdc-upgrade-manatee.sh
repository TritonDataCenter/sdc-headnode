#!/usr/bin/bash
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#


LOG_FILENAME=/tmp/manatee-upgrade.$$.log
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

function find_moray_service
{
    moray_svc_uuid=$(sdc-sapi /services?name=moray | json -Ha uuid)
        if [[ -z ${moray_svc_uuid} ]]; then
        echo ""
        fatal "unable to get moray service uuid from SAPI."
    fi
    echo "moray service_uuid is ${moray_svc_uuid}"
}

function find_moray_instances
{
    echo "Finding all moray instances & servers."
    moray_instances=$(sdc-vmapi '/vms?tag.smartdc_role=moray&state=running' | \
                      json -d'+' -Ha uuid server_uuid)

}

function restart_moray
{
    local server=${1:37}
    local zone=${1:0:36}
    echo "Restarting moray services for ${zone}"
    sdc-oneachnode -n ${server} \
        "svcadm -z ${zone} restart -s moray-2021;\
         svcadm -z ${zone} restart -s moray-2022;\
         svcadm -z ${zone} restart -s moray-2023;\
         svcadm -z ${zone} restart -s moray-2024;"
}

function find_manatees
{
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
#   sync - stable primary/sync two-node config.
#   full - stable primary/sync/async config.
function wait_for_manatee
{
    local wait_for=$1
    local cmd=
    local target=
    local desc=
    local result=
    local count=0
    case "${wait_for}" in
        sync)
            cmd='json sdc.primary.repl.sync_state'
            target='sync'
            desc='two-node sync'
            ;;
        full)
            cmd='json sdc.sync.repl.sync_state'
            target='async'
            desc='three-node state'
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
        if [[ ${result} == ${target} ]]; then
            continue;
        elif [[ ${count} -gt 24 ]]; then
            fatal "Timeout (>120s) waiting for manatee to reach ${wait_for}"
        else
            count=$((${count} + 1))
            sleep 5
        fi
    done
    echo "Done! Manatee reached ${wait_for}"
}

function install_from_updates
{
    local image=$1
    local exists=$(sdc-imgadm get ${image} | json -H uuid)
    if [[ -z "${exists}" ]]; then
        echo "Fetching image ${image} from updates.joyent.com"
        sdc-imgadm import ${image} -S https://updates.joyent.com --skip-owner-check
        if [[ $? != 0 ]]; then
            echo ""
            fatal "Couldn't import manatee upgrade image from updates.joyent.com"
        fi
    fi
}

function install_manatee_image
{
    install_from_updates ${manatee_image_uuid}
    local servers=${primary_server},${sync_server},${async_server}
    local result=$(sdc-oneachnode -n ${servers} \
        "imgadm avail | grep ${manatee_image_uuid}")
    if [[ $? != 0 ]]; then
        echo ""
        fatal "image not available for import on all servers: ${result}"
    fi
    echo "Importing image ${manatee_image_uuid} to ${servers}"
    sdc-oneachnode -n ${servers} "imgadm import ${manatee_image_uuid}"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Couldn't import managee image to all servers."
    fi
}

function disable_manatee
{
    local server=$1
    local zone=$2
    echo "Disabling manatee services in ${zone}"
    sdc-oneachnode -n ${server} \
    "svcadm -z ${zone} disable -s manatee-sitter;\
     svcadm -z ${zone} disable -s manatee-snapshotter;\
     svcadm -z ${zone} disable -s manatee-backupserver;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Couldn't disable manatee services in ${zone}"
    fi
}

# should operate on headnode manatee.
function upgrade_manatee_sapi_user_script
{
    local manatee=$(vmadm lookup -1 alias=manatee0)
    local user_script="/usbkey/default/user-script.common"
    local old_script="/var/tmp/manatee-user-script.$$.old"
    local sapi_payload="/var/tmp/sapi-user-script-payload.$$.json"

    echo "Archiving existing userscript in ${old_script}"
    vmadm get ${manatee} > ${old_script}

    echo "Updating SAPI userscript for manatee"
    local manatee_svc=$(sdc-sapi '/services?name=manatee' | json -Ha uuid)
    /usr/vm/sbin/add-userscript ${user_script} \
        | json -e "this.payload={metadata: this.set_customer_metadata}" payload \
        > ${sapi_payload}
    sdc-sapi /services/${manatee_svc} -X PUT -d@${sapi_payload}
    echo "SAPI updated."
}

function upgrade_manatee_instance_user_script
{
    local server=$1
    local zone=$2
    local user_script="user-script.common"
    local destdir="/var/tmp"
    local hn_file="/usbkey/default/${user_script}"
    local cn_file="${destdir}/${user_script}"

    echo "Updating remote user-script for ${zone}"
    sdc-oneachnode -n ${server} -g ${hn_file} -d ${destdir}
    sdc-oneachnode -n ${server} \
        "echo {} | /usr/vm/sbin/add-userscript ${cn_file} | vmadm update ${zone}"
    echo "User script updated"
}

# Should only be necessary on headnodes (new nodes should have newer
# platforms without this bug)
function workaround_OS2275
{
    local server=$1
    local zone=$2
    local headnode=$(sdc-cnapi /servers/${server} | json -Ha headnode)
    if [[ ${headnode} == "true" ]]; then
        echo "Checking and correcting for 0GB quota on headnode ${server}"
        sdc-oneachnode -n ${server} \
            "headnode=\$(sysinfo | json \"Boot Parameters\".headnode); \
                 if [[ \${headnode} == \"true\" ]]; then \
                     quota=\$(vmadm get ${zone} | json quota); \
                 if [[ \${quota} == 0 ]]; then \
                     vmadm update ${zone} quota=50;
                 fi
             fi"
    fi
}

# Anything having CWD in a zone will clobber the reprovision. This is
# a specific problem in AMS-1 headnode platform
function workaround_cwd_in_zone
{
    local server=$1
    local zone=$2
    local headnode=$(sdc-cnapi /servers/${server} | json -Ha headnode)
    local dc=$(sdc-cnapi /servers/${server} | json -Ha datacenter)
    if [[ ${headnode} == "true" && ${dc} == "eu-ams-1" ]]; then
        echo "Stopping and remounting datasets from ${zone}"
        sdc-oneachnode -n ${server} \
            "vmadm stop ${zone}; \
             zfs unmount zones/cores/${zone}; \
             zfs unmount -f zones/${zone}; \
             zfs mount zones/${zone}; \
             zfs mount zones/cores/${zone};
            "
    fi
}

function reprovision_manatee
{
    local server=$1
    local zone=$2
    local current_image=$(sdc-vmapi /vms/${zone} -f | json image_uuid)

    # OS-2275
    workaround_OS2275 ${server} ${zone}
    workaround_cwd_in_zone ${server} ${zone}

    if [[ ${current_image} == ${manatee_image_uuid} ]]; then
        echo "Manatee ${zone} already at image ${manatee_image_uuid}, skipping."
    else
        echo "Reprovisioning ${zone} to ${manatee_image_uuid}..."
        sdc-oneachnode -n ${server} \
            "echo '{}' | json -e \"this.image_uuid='${manatee_image_uuid}'\" \
            | vmadm reprovision ${zone}"
        if [[ $? != 0 ]]; then
            echo ""
            fatal "Failed reprovisioning manatee in ${zone}, stopping."
        fi
    fi
}

echo "!! log file is ${LOG_FILENAME}"

manatee_image_uuid=$1
if [[ -z ${manatee_image_uuid} ]]; then
    cat >&2 <<EOF
Usage: $0 <manatee_image>
EOF
    exit 1
fi

# mainline - starting with async:
# disable it
# wait for two-node stable state
# reprovision
# wait for full state
# repeat!
find_manatees
install_manatee_image

upgrade_manatee_sapi_user_script

disable_manatee ${async_server} ${async_manatee}
wait_for_manatee sync
upgrade_manatee_instance_user_script ${async_server} ${async_manatee}
reprovision_manatee ${async_server} ${async_manatee}
wait_for_manatee full

disable_manatee ${sync_server} ${sync_manatee}
wait_for_manatee sync
upgrade_manatee_instance_user_script ${sync_server} ${sync_manatee}
reprovision_manatee ${sync_server} ${sync_manatee}
wait_for_manatee full

disable_manatee ${primary_server} ${primary_manatee}
wait_for_manatee sync
upgrade_manatee_instance_user_script ${primary_server} ${primary_manatee}
wait_for_ops "Check reconnection: MORAY-194, ZAPI-434. [enter] to continue."
reprovision_manatee ${primary_server} ${primary_manatee}
wait_for_manatee full

