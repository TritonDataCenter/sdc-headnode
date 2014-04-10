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

if [[ -z "$ASSETS_URL" ]]; then
    fatal "ASSETS_URL environment variable must be set"
fi

if [[ ! -d /opt/smartdc/agents/bin ]]; then
    setup_agents
    if [[ -z ${ENABLE_6x_WORKAROUNDS} ]]; then
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
