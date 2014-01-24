#!/usr/bin/bash
#
# Utilities for the incr-upgrade scripts.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}


function wait_for_wf_drain {
    local running
    local queued

    echo "Wait up to 5 minutes for workflow to drain of running/queued jobs."
    for i in {1..60}; do
        sleep 5
        echo -n '.'
        # If sdc zone is rebooting, then can't call sdc-vmapi here, just
        # presume the job is still running.
        running="$(sdc-workflow /jobs?limit=20\&execution=running | json -Ha uuid)"
        if [[ -n "$running" ]]; then
            continue
        fi
        queued="$(sdc-workflow /jobs?limit=20\&execution=queued | json -Ha uuid)"
        if [[ -n "$queued" ]]; then
            continue
        fi
        break
    done
    echo ""
    if [[ -n "$running" || -n "$queued" ]]; then
        fatal "workflow did not drain of running and queued jobs"
    fi
    echo "Workflow cleared of running and queued jobs."
}


# Set cloudapi readonly mode.
#
# Usage:
#   cloudapi_readonly_mode true         # put in readonly mode
#   cloudapi_readonly_mode false        # take out of readonly mode
function cloudapi_readonly_mode {
    local readonly=$1
    if [[ "$readonly" != "true" && "$readonly" != "false" ]]; then
        fatal "invalid argument: $readonly (must be 'true' or 'false')"
    fi

    UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
    SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    [[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
    CLOUDAPI_SVC=$(sdc-sapi /services?name=cloudapi\&application_uuid=$SDC_APP | json -H 0.uuid)
    [[ -n "$CLOUDAPI_SVC" ]] || fatal "could not determine sdc 'cloudapi' SAPI svc"
    CLOUDAPI_ZONE=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~cloudapi)
    [[ -n "$CLOUDAPI_ZONE" ]] || fatal "could not find cloudapi zone on headnode"

    # Get current setting.
    curr=$(sdc-sapi /services/$CLOUDAPI_SVC | json -H metadata.CLOUDAPI_READONLY)
    if [[ "$curr" == "$readonly" ]]; then
        echo "cloudapi is already configured for CLOUDAPI_READONLY=$curr"
        return
    fi
    sdc-sapi /services/$CLOUDAPI_SVC -X PUT -d"{\"metadata\":{\"CLOUDAPI_READONLY\":$readonly}}"

    # TODO: Do this for N cloudapi instances.
    zlogin ${CLOUDAPI_ZONE} "/opt/smartdc/config-agent/build/node/bin/node /opt/smartdc/config-agent/agent.js -s"
    # Workaround PUBAPI-802 and manually restart each cloudapi instance.
    svcs -z $CLOUDAPI_ZONE -Ho fmri cloudapi | xargs -n1 svcadm -z $CLOUDAPI_ZONE restart

    # TODO: add readonly status to /--ping on cloudapi and watch for that.
}
