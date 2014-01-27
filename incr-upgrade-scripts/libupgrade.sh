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


# Update /usbkey/extra/$role in prep for (re)provision of a zone with that
# role.
function copy_usbkey_extra_files
{
    local role=$1

    cp default/* /usbkey/default

    rm -f /usbkey/extra/$role/setup
    mkdir -p /usbkey/extra/$role
    if [[ -f zones/$role/setup ]]; then
        cp zones/$role/setup /usbkey/extra/$role/setup
    fi
    rm -f /usbkey/extra/$role/configure
    if [[ -f zones/$role/configure ]]; then
        cp zones/$role/configure /usbkey/extra/$role/configure
    fi
    rm -f /usbkey/extra/$role/setup.common
    if [[ -f /usbkey/default/setup.common ]]; then
        cp /usbkey/default/setup.common /usbkey/extra/$role/setup.common
    fi
    rm -f /usbkey/extra/$role/configure.common
    if [[ -f /usbkey/default/configure.common ]]; then
        cp /usbkey/default/configure.common /usbkey/extra/$role/configure.common
    fi
    #TODO: should update /usbkey/extras/bashrc from /usbkey/rc/
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



function wait_until_zone_in_dns() {
    local uuid=$1
    local alias=$2
    local domain=$3
    [[ -n "$uuid" ]] || fatal "wait_until_zone_in_dns: no 'uuid' given"
    [[ -n "$alias" ]] || fatal "wait_until_zone_in_dns: no 'alias' given"
    [[ -n "$domain" ]] || fatal "wait_until_zone_in_dns: no 'domain' given"

    local ip=$(vmadm get $uuid | json nics.0.ip)
    [[ -n "$ip" ]] || fatal "no IP for the new $alias ($uuid) zone"

    echo "Wait up to 2 minutes for $alias zone to enter DNS."
    for i in {1..24}; do
        sleep 5
        echo '.'
        in_dns=$(dig $domain +short | (grep $ip || true))
        if [[ "$in_dns" == "$ip" ]]; then
            break
        fi
    done
    in_dns=$(dig $domain +short | (grep $ip || true))
    if [[ "$in_dns" != "$ip" ]]; then
        fatal "New $alias ($uuid) zone's IP $ip did not enter DNS: 'dig $domain +short | grep $ip'"
    fi
}


function wait_until_zone_out_of_dns() {
    local uuid=$1
    local alias=$2
    local domain=$3
    [[ -n "$uuid" ]] || fatal "wait_until_zone_out_of_dns: no 'uuid' given"
    [[ -n "$alias" ]] || fatal "wait_until_zone_out_of_dns: no 'alias' given"
    [[ -n "$domain" ]] || fatal "wait_until_zone_out_of_dns: no 'domain' given"

    local ip=$(vmadm get $uuid | json nics.0.ip)
    [[ -n "$ip" ]] || fatal "no IP for the new $alias ($uuid) zone"

    echo "Wait up to 2 minutes for $alias zone to leave DNS."
    for i in {1..24}; do
        sleep 5
        echo '.'
        in_dns=$(dig $domain +short | (grep $ip || true))
        if [[ -z "$in_dns" ]]; then
            break
        fi
    done
    in_dns=$(dig $domain +short | (grep $ip || true))
    if [[ -n "$in_dns" ]]; then
        fatal "New $alias ($uuid) zone's IP $ip did not leave DNS: 'dig $domain +short | grep $ip'"
    fi
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
