#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2021 Joyent, Inc.
#

exec 4>/dev/console

# keep a copy of the output in /tmp/joysetup.$$ for later viewing
exec > >(tee /var/log/agent-setup.log)
exec 2>&1

set -o errexit
set -o pipefail
# BASHSTYLED
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# Get the OS type.
OS_TYPE=$(uname -s)

BASEDIR=/opt/smartdc

if [[ $OS_TYPE == "Linux" ]]; then
    # echo "TODO: Linux - could we return some system(d) state here?"
    # exit 0
    BASEDIR=/opt/triton
    PATH=$PATH:$BASEDIR/bin
    export PATH
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

# Create the agent setup file.
SETUP_FILE=/var/lib/setup.json
if [[ -n ${MOCKCN} ]]; then
    SETUP_FILE="/mockcn/${MOCKCN_SERVER_UUID}/setup.json"
fi
if [[ $OS_TYPE == "Linux" ]]; then
    SETUP_FILE="${BASEDIR}/config/triton-setup-state.json"
    # Put the triton tooling on the path.
    export PATH=$PATH:/usr/node/bin:/usr/triton/bin
fi
if [[ ! -f $SETUP_FILE ]]; then
    fatal "Setup file does not exist: ${SETUP_FILE}"
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
    local logfile="${BASEDIR}/agents/log/install.log"

    if [[ $OS_TYPE == "Linux" ]]; then
        logfile="/var/log/triton-agent-install.log"
        /usr/triton/bin/install-default-agents &> "${logfile}"

        # Why are we sleeping? It's pretty much a hack. net-agent needs to
        # start up and push all the nics to NAPI. Without this, linux server
        # set up blows by so fast the reboot happens in mere seconds and reboots
        # before net-agent has a chance to get going. This results in the nics
        # not being owned in NAPI, which causes booter to give the newly setup
        # CN the default PI, which may not be Linux. You end up with a server
        # running SmartOS and showing up unsetup because it can't read the
        # zpool.
        # This is totally a race, and we're just going to sleep a bit to give
        # net-agent the chance it needs to win that race. Various testing shows
        # net-agent takes about 10s from start up to pushing the nics. So we'll
        # give it 30s.
        # SmartOS server setup takes longer what with touching the setup file
        # and restarting ur and such. I definitely believe that this race
        # condition also exists for SmartOS, but server setup just takes more
        # time after agents run so that we've never actually run into it.
        # But thus far, before adding Linux, CNs are almost always set up
        # without reassigning to a different PI. The effect is that it boots
        # the default PI, server setup completes, and if net-agent isn't done
        # it'll reboot the default PI again anyway, but it's *not* running a
        # different OS, and it *can* read the zpool. So net-agent just starts
        # up and the nics get adopted anyway. Worst case scenario, in a SmartOS
        # only world, if you actually did assign a non-default PI and reboot
        # before server setup you'll just be running the wrong PI at the end.
        # This problem is *invisible* if you're running SmartOS only, and it
        # may very well show up in reverse if your default PI is Linux and you
        # want the occasional SmartOS CN.
        # The *right* thing to do would be to have a workflow step that polls
        # NAPI for nics owned by the server UUID, but napiUrl isn't currently
        # passed into the workflow job like cnapiUrl and assetUrl are, and
        # updating that is not trivial. Hopefully this can be addressed in the
        # near future and this hack removed to resolve this issue once and for
        # all. Until then, enjoy your nap.
        # Please don't let this comment still be here in 10 years.
        sleep 30
        return
    fi

    AGENTS_SHAR_URL=${ASSETS_URL}/extra/agents/latest
    AGENTS_SHAR_PATH=./agents-installer.sh

    cd /var/run

    /usr/bin/curl --silent --show-error ${AGENTS_SHAR_URL} -o $AGENTS_SHAR_PATH

    if [[ ! -f $AGENTS_SHAR_PATH ]]; then
        fatal "failed to download agents setup script"
    fi

    local logfile="${BASEDIR}/agents/log/install.log"
    mkdir -p "${BASEDIR}/agents/log"
    /usr/bin/bash $AGENTS_SHAR_PATH &> "${logfile}"

    if [[ -n ${MOCKCN} && -f "${BASEDIR}/mockcn/bin/fix-agents.sh" ]]; then
        ${BASEDIR}/mockcn/bin/fix-agents.sh
    fi

    result=$(tail -n 1 "${logfile}")
}

setup_tools()
{
    if [[ $OS_TYPE == "Linux" ]]; then
        echo "We are not setting up agents on Linux servers"
        return
    fi

    TOOLS_URL="${ASSETS_URL}/extra/joysetup/cn_tools.tar.gz"
    TOOLS_FILE="/tmp/cn_tools.$$.tar.gz"

    if ! /usr/bin/curl -sSf "${TOOLS_URL}" -o "${TOOLS_FILE}"; then
        rm -f "${TOOLS_FILE}"
        fatal "failed to download tools tarball"
    fi

    mkdir -p "${BASEDIR}"
    if ! /usr/bin/tar xzof "${TOOLS_FILE}" -C "${BASEDIR}"; then
        rm -f "${TOOLS_FILE}"
        fatal "failed to extract tools tarball"
    fi

    #
    # The "cn_tools.tar.gz" tarball contains an up-to-date copy of some set
    # of USB key files, e.g. the iPXE bootloader.  Run the update tool now
    # to ensure the USB key is up-to-date for the next reboot.  We use the
    # --ignore-missing flag in case this is a compute node that does not
    # have a USB key.
    #
    if ! "${BASEDIR}/bin/sdc-usbkey" -v update --ignore-missing; then
        fatal "failed to update USB key from tools tarball"
    fi

    rm -f "${TOOLS_FILE}"
}

if [[ -z "$ASSETS_URL" ]]; then
    fatal "ASSETS_URL environment variable must be set"
fi

if [[ $OS_TYPE == "SunOS" && -z ${MOCKCN} ]]; then
    if setup_state_not_seen "tools_installed"; then
        setup_tools
        update_setup_state "tools_installed"
    fi
fi

if [[ -n ${MOCKCN} ]]; then
    # When we're mocking a CN we might already have agents installed,
    # in the future, we'll want to have heartbeater and provisioner notice
    # there's a new server too. For now we just pretend everything worked.
    update_setup_state "agents_installed"
    mark_as_setup
elif [[ ! -d "${BASEDIR}/agents/bin" ]]; then
    setup_agents
    update_setup_state "agents_installed"
    mark_as_setup
fi

# Return SmartDC services statuses on STDOUT:
if [[ $OS_TYPE == "SunOS" ]]; then
    echo $(svcs -a -o STATE,FMRI|grep smartdc)
elif [[ $OS_TYPE == "Linux" ]]; then
    echo "TODO: Linux - could we return some system(d) state here?"
fi

# Scripts to be executed by Ur need to explicitly return an exit status code:
exit 0
