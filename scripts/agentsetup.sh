#!/usr/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

exec 4>/dev/console

set -o errexit
set -o pipefail
# BASHSTYLED
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# Load SYSINFO_* and CONFIG_* values
. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

# flag set when we're on a 6.x platform
ENABLE_6x_WORKAROUNDS=
if [[ -z ${SYSINFO_SDC_Version} ]]; then
    ENABLE_6x_WORKAROUNDS="true"
fi

# Mock CN is used for creating "fake" Compute Nodes in SDC for testing.
MOCKCN=
if [[ $(zonename) != "global" && -n ${MOCKCN_SERVER_UUID} ]]; then
    MOCKCN="true"
fi

fatal()
{
    # Any error message should be redirected to stderr:
    echo "Error: $1" 1>&2
    exit 1
}

SETUP_FILE=/var/lib/setup.json
if [[ -n ${MOCKCN} ]]; then
    SETUP_FILE="/mockcn/${MOCKCN_SERVER_UUID}/setup.json"
fi

function update_setup_state
{
    STATE=$1

    chmod 600 $SETUP_FILE
    cat "$SETUP_FILE" | json -e \
        "this.current_state = '$STATE';
         this.last_updated = new Date().toISOString();
         this.seen_states.push('$STATE');" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
}

function setup_state_not_seen
{
    STATE=$1

    IS_SEEN=$(json -f ${SETUP_FILE} -e \
        "this.result = this.seen_states.filter(
            function(e) { return e === '$state' })[0]" result)
    if [[ -z "$IS_SEEN" ]]; then
        return 0
    else
        return 1
    fi
}

function mark_as_setup
{
    chmod 600 $SETUP_FILE
    # Update the setup state file with the new value
    cat "$SETUP_FILE" | json -e "this.complete = true;
         this.current_state = 'setup_complete';
         this.seen_states.push('setup_complete');
         this.last_updated = new Date().toISOString();" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE

    if [[ -n ${MOCKCN} ]]; then
        json -e 'this.Setup = "true"' \
            < /mockcn/${MOCKCN_SERVER_UUID}/sysinfo.json \
            > /mockcn/${MOCKCN_SERVER_UUID}/sysinfo.json.new \
            && mv /mockcn/${MOCKCN_SERVER_UUID}/sysinfo.json.new \
            /mockcn/${MOCKCN_SERVER_UUID}/sysinfo.json
        return
    fi

    sysinfo -u
}

setup_agents()
{
    AGENTS_SHAR_URL=${ASSETS_URL}/extra/agents/latest
    AGENTS_SHAR_PATH=./agents-installer.sh

    cd /var/run

    if [[ -n ${ENABLE_6x_WORKAROUNDS} ]]; then
        AGENTS_SHAR_URL=${ASSETS_URL}/extra/agents/latest-65-initial
        AGENTS_SHAR_PATH=./agents-installer-initial.sh

        /usr/bin/curl --silent --show-error ${AGENTS_SHAR_URL} \
            -o $AGENTS_SHAR_PATH

        if [[ ! -f $AGENTS_SHAR_PATH ]]; then
            fatal "failed to download agents setup script"
        fi

        mkdir -p /opt/smartdc/agents/log
        /usr/bin/bash $AGENTS_SHAR_PATH \
            &>/opt/smartdc/agents/log/initial-install.log
        result=$(tail -n 1 /opt/smartdc/agents/log/initial-install.log)

        # fall through to the normal logic but for upgrade
        AGENTS_SHAR_URL=${ASSETS_URL}/extra/agents/latest-65-upgrade
        AGENTS_SHAR_PATH=./agents-installer-upgrade.sh
    fi

    /usr/bin/curl --silent --show-error ${AGENTS_SHAR_URL} -o $AGENTS_SHAR_PATH

    if [[ ! -f $AGENTS_SHAR_PATH ]]; then
        fatal "failed to download agents setup script"
    fi

    mkdir -p /opt/smartdc/agents/log
    /usr/bin/bash $AGENTS_SHAR_PATH &>/opt/smartdc/agents/log/install.log

    if [[ -n ${MOCKCN} && -f "/opt/smartdc/mockcn/bin/fix-agents.sh" ]]; then
        /opt/smartdc/mockcn/bin/fix-agents.sh
    fi

    result=$(tail -n 1 /opt/smartdc/agents/log/install.log)
}

setup_tools()
{
    TOOLS_URL="${ASSETS_URL}/extra/joysetup/cn_tools.tar.gz"
    TOOLS_FILE="/tmp/cn_tools.$$.tar.gz"

    if ! /usr/bin/curl -sSf "${TOOLS_URL}" -o "${TOOLS_FILE}"; then
        rm -f "${TOOLS_FILE}"
        fatal "failed to download tools tarball"
    fi

    mkdir -p /opt/smartdc
    if ! /usr/bin/tar xzof "${TOOLS_FILE}" -C /opt/smartdc; then
        rm -f "${TOOLS_FILE}"
        fatal "failed to extract tools tarball"
    fi

    rm -f "${TOOLS_FILE}"
}

# just run the config-agent in synchronous mode to write initial configs and
# let agents start running before creating core zones
setup_config_agent()
{
    AGENTS_DIR=/opt/smartdc/agents
    CONFIGURABLE_AGENTS="net-agent vm-agent"

    local sapi_url=http://${CONFIG_sapi_domain}
    local prefix=$AGENTS_DIR/lib/node_modules/config-agent
    local tmpfile=/tmp/agent.$$.xml

    sed -e "s#@@PREFIX@@#${prefix}#g" \
        ${prefix}/smf/manifests/config-agent.xml > ${tmpfile}
    mv ${tmpfile} $AGENTS_DIR/smf/config-agent.xml

    mkdir -p ${prefix}/etc
    local file=${prefix}/etc/config.json
    cat >${file} <<EOF
{
    "logLevel": "info",
    "pollInterval": 15000,
    "sapi": {
        "url": "${sapi_url}"
    }
}
EOF

    for agent in $CONFIGURABLE_AGENTS; do
        local instance_uuid=$(cat /opt/smartdc/agents/etc/$agent)
        local tmpfile=/tmp/add_dir.$$.json

        if [[ -z ${instance_uuid} ]]; then
            fatal "Unable to get instance_uuid from /opt/smartdc/agents/etc/$agent"
        fi

        cat ${file} | json -e "
            this.instances = this.instances || [];
            this.instances.push('$instance_uuid');
            this.localManifestDirs = this.localManifestDirs || {};
            this.localManifestDirs['$instance_uuid'] = ['$AGENTS_DIR/lib/node_modules/$agent'];
        " >${tmpfile}
        mv ${tmpfile} ${file}
    done

    ${prefix}/build/node/bin/node ${prefix}/agent.js -s -f /opt/smartdc/agents/lib/node_modules/config-agent/etc/config.json

    for agent in $CONFIGURABLE_AGENTS; do
        svccfg import $AGENTS_DIR/smf/$agent.xml
    done

    svccfg import $AGENTS_DIR/smf/config-agent.xml
    svcadm enable config-agent
}

# "sapi_adopt" means adding an agent "instance" to SAPI
# $1: service_name
# $2: instance_uuid
function sapi_adopt()
{
    local service_name=$1
    local sapi_url=http://${CONFIG_sapi_domain}

    local service_uuid=""
    local sapi_instance=""
    local i=0
    while [[ -z ${service_uuid} && ${i} -lt 48 ]]; do
        service_uuid=$(curl "${sapi_url}/services?type=agent&name=${service_name}"\
            -sS -H accept:application/json | json -Ha uuid)
        if [[ -z ${service_uuid} ]]; then
            echo "Unable to get server_uuid from sapi yet.  Sleeping..."
            sleep 5
        fi
        i=$((${i} + 1))
    done
    [[ -n ${service_uuid} ]] || \
    fatal "Unable to get service_uuid for role ${service_name} from SAPI"

    uuid=$2

    i=0
    while [[ -z ${sapi_instance} && ${i} -lt 48 ]]; do
        sapi_instance=$(curl ${sapi_url}/instances -sS -X POST \
            -H content-type:application/json \
            -d "{ \"service_uuid\" : \"${service_uuid}\", \"uuid\" : \"${uuid}\" }" \
        | json -H uuid)
        if [[ -z ${sapi_instance} ]]; then
            echo "Unable to adopt ${service_name} ${uuid} into sapi yet.  Sleeping..."
            sleep 5
        fi
        i=$((${i} + 1))
    done

    [[ -n ${sapi_instance} ]] || fatal "Unable to adopt ${uuid} into SAPI"
    echo "Adopted service ${service_name} to instance ${uuid}"
}

# For adopting agent instances on SAPI we first generate a UUID and then create
# an instance with that UUID. The instance UUID should written to a place where
# it doesn't get removed on upgrades so agents keep their UUIDs. Also, when
# setting up config-agent we write the instances UUIDs to its config file
function adopt_agents()
{
    AGENTS_DIR=/opt/smartdc/agents
    CONFIGURABLE_AGENTS="net-agent vm-agent"

    for agent in $CONFIGURABLE_AGENTS; do
        instance_uuid=$(uuid -v4)
        echo $instance_uuid > $AGENTS_DIR/etc/$agent
        sapi_adopt $agent $instance_uuid
    done
}

if [[ -z "$ASSETS_URL" ]]; then
    fatal "ASSETS_URL environment variable must be set"
fi

if setup_state_not_seen "tools_installed"; then
    if [[ -z ${MOCKCN} ]]; then
        setup_tools
    fi
    update_setup_state "tools_installed"
fi

if [[ ! -d /opt/smartdc/agents/bin ]]; then
    setup_agents
    if [[ -z ${ENABLE_6x_WORKAROUNDS} ]]; then
        adopt_agents
        setup_config_agent
        update_setup_state "agents_installed"
        mark_as_setup
    fi
elif [[ -n ${MOCKCN} ]]; then
    # When we're mocking a CN we might already have agents installed,
    # in the future, we'll want to have heartbeater and provisioner notice
    # there's a new server too. For now we just pretend everything worked.
    update_setup_state "agents_installed"
    mark_as_setup
fi

# Return SmartDC services statuses on STDOUT:
echo $(svcs -a -o STATE,FMRI|grep smartdc)

# Scripts to be executed by Ur need to explicitly return an exit status code:
exit 0
