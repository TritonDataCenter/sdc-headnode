#!/usr/bin/bash
#
# Copyright (c) 2014, Joyent, Inc. All rights reserved.
#



LOG_FILENAME=/tmp/manatee-v2-remote-upgrade.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin:$PATH

set -o errexit
set -o xtrace
set -o pipefail

function fatal
{
    echo "FATAL: $*" >&2
    exit 2
}

function usage
{
    cat >&2 <<EOF
Usage: $0 <instance_uuid> <tarball_path>
EOF
    exit 1
}

function manatee_stat
{
    # manatee-stat exists in different places depending on the manatee version
    local m_stat=
    if [[ -f /zones/${manatee_instance}/root/opt/smartdc/manatee/bin/manatee-stat ]]; then
        m_stat="/opt/smartdc/manatee/bin/manatee-stat -p \$ZK_IPS"
    elif [[ -f /zones/${manatee_instance}/root/opt/smartdc/manatee/node_modules/manatee/bin/manatee-stat ]]; then
        m_stat="/opt/smartdc/manatee/node_modules/manatee/bin/manatee-stat -p \$ZK_IPS"
    else
        fatal "Can't find manatee-stat."
    fi
    local result=$(zlogin ${manatee_instance} "source /opt/smartdc/etc/zk_ips.sh; ${m_stat}");
    echo ${result}
}

function wait_for_manatee
{
    local expect=$1
    local result=
    local count=0

    while [[ ${result} != ${expect} ]]; do
        result=$(manatee_stat | json -e '
            if (Object.keys(this.sdc).length===0) {
                this.mode = "empty";
            } else if (this.sdc.primary && this.sdc.sync && this.sdc.async) {
                var up = this.sdc.async.repl && !this.sdc.async.repl.length && Object.keys(this.sdc.async.repl).length === 0;
                if (up && this.sdc.sync.repl && this.sdc.sync.repl.sync_state == "async") {
                    this.mode = "async";
                }
            } else if (this.sdc.primary && this.sdc.sync) {
                var up = this.sdc.sync.repl && !this.sdc.sync.repl.length && Object.keys(this.sdc.sync.repl).length === 0;
                if (up && this.sdc.primary.repl && this.sdc.primary.repl.sync_state == "sync") {
                    this.mode = "sync";
                }
            } else if (this.sdc.primary) {
                var up = this.sdc.primary.repl && !this.sdc.primary.repl.length && Object.keys(this.sdc.primary.repl).length === 0;
                if (up) {
                    this.mode = "primary";
                }
            }

            if (!this.mode) {
                this.mode = "transition";
            }' mode)
        if [[ ${result} == ${expect} ]]; then
            continue;
        elif [[ ${count} -gt 24 ]]; then
            fatal "Timeout (120s) waiting for manatee to reach ${target}"
        else
            count=$((${count} + 1))
            sleep 5
        fi
    done
}

function crack_tarball
{
    local dest=/zones/${manatee_instance}/root/opt/smartdc
    if [[ ! -d ${dest} ]]; then
        fatal "No such destination: ${dest}"
    fi
    mkdir -p ${dest}/manatee-new
    tar zxf ${tarball} -C ${dest}/manatee-new
}

function swap_code
{
    # this can race with config-agent
    svcadm -z ${manatee_instance} disable config-agent
    zlogin ${manatee_instance} mv /opt/smartdc/manatee /opt/smartdc/manatee-old
    zlogin ${manatee_instance} mv /opt/smartdc/manatee-new /opt/smartdc/manatee
    svcadm -z ${manatee_instance} enable config-agent
}

function ensure_correct_config
{

    svcadm -z ${manatee_instance} disable -s config-agent
    zlogin ${manatee_instance} rm -f /opt/smartdc/manatee/etc/sitter.json
    svcadm -z ${manatee_instance} enable -s config-agent

    # wait until config appears
    local count=0
    while [[ ! -f /zones/${manatee_instance}/root/opt/smartdc/manatee/etc/sitter.json ]]; do
        if [[ ${count} -gt 12 ]]; then
            fatal "Timeout waiting for config in ${manatee_instance}"
        else
            count=$((${count} + 1))
            sleep 5
        fi
    done
}

function import_smf
{
    zlogin ${manatee_instance} svccfg import /opt/smartdc/manatee/smf/manifests/sitter.xml
}

function touch_sync_state
{
    cookieLocation=$(zlogin ${manatee_instance} json -f /opt/smartdc/manatee/etc/sitter.json \
                     postgresMgrCfg.syncStateCheckerCfg.cookieLocation)
    if [[ ! -f ${cookieLocation} ]]; then
        zlogin ${manatee_instance} touch ${cookieLocation}
        zlogin ${manatee_instance} chown postgres:postgres ${cookieLocation}
    fi
}

# seems unnecessary, but PATH variable in the smf manifest doesn't seem
# to be respected in this situation?
function node_version
{
    local old_node=/opt/local/bin/node
    local new_node=/opt/smartdc/manatee/build/node/bin/node
    zlogin ${manatee_instance} mv ${old_node} /opt/local/bin/node0.8
    zlogin ${manatee_instance} ln -s ${new_node} ${old_node}
}

# if sitter up, get current state
#   bring sitter down
#   wait for state-1
# endif
# get current state
# bring sitter up
# wait for state+1
function restart_sitter
{
    local state=$(svcs -Ho state -z ${manatee_instance} manatee-sitter)
    local final_state=
    if [[ ${state} == "online" ]]; then
        # assume this is for single-node restart.
        svcadm -z ${manatee_instance} disable manatee-sitter
        wait_for_manatee empty
        final_state="primary"
    elif [[ ${state} == "disabled" ]]; then
        final_state="sync"
    else
        fatal "Manatee ${manatee_instance} in unexpected state ${state}"
    fi
    svcadm -z ${manatee_instance} enable manatee-sitter
    wait_for_manatee ${final_state}
}

# vars, params

manatee_instance=$1
if [[ -z ${manatee_instance} ]]; then
    usage
fi

tarball=$2
if [[ ! -f ${tarball} ]]; then
    usage
fi

echo "!! log file is ${LOG_FILENAME}"

# mainline

crack_tarball
swap_code
ensure_correct_config
import_smf
touch_sync_state
node_version
restart_sitter

echo "done."

