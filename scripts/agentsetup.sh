#!/usr/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

exec 4>/dev/console

set -o errexit
set -o pipefail
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace


PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH

fatal()
{
    # Any error message should be redirected to stderr:
    echo "Error: $1" 1>&2
    exit 1
}


SETUP_FILE=/var/lib/setup.json

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
}

setup_agents()
{
    AGENTS_SHAR_URL=${ASSETS_URL}/extra/agents/latest
    AGENTS_SHAR_PATH=./agents-installer.sh

    cd /var/run
    /usr/bin/curl --silent --show-error ${AGENTS_SHAR_URL} -o $AGENTS_SHAR_PATH

    if [[ ! -f $AGENTS_SHAR_PATH ]]; then
        fatal "failed to download agents setup script"
    fi

    mkdir -p /opt/smartdc/agents/log
    /usr/bin/bash $AGENTS_SHAR_PATH &>/opt/smartdc/agents/log/install.log
    result=$(tail -n 1 /opt/smartdc/agents/log/install.log)
}

if [[ -z "$ASSETS_URL" ]]; then
    fatal "ASSETS_URL environment variable must be set"
fi

if [[ ! -d /opt/smartdc/agents/bin ]]; then
    setup_agents
    update_setup_state "agents_installed"
    mark_as_setup
fi

# Return SmartDC services statuses on STDOUT:
echo $(svcs -a -o STATE,FMRI|grep smartdc)

# Scripts to be executed by Ur need to explicitly return an exit status code:
exit 0
