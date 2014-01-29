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
    local ip=$4
    [[ -n "$uuid" ]] || fatal "wait_until_zone_out_of_dns: no 'uuid' given"
    [[ -n "$alias" ]] || fatal "wait_until_zone_out_of_dns: no 'alias' given"
    [[ -n "$domain" ]] || fatal "wait_until_zone_out_of_dns: no 'domain' given"
    if [[ -z "$ip" ]]; then
        ip=$(vmadm get $uuid | json nics.0.ip)
    fi
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



# Update the customer_metadata.user-script on a zone in preparation for
# 'vmadm reprovision'. Also save it in "user-scripts/" for possible rollback.
function update_svc_user_script {
    local uuid=$1
    local image_uuid=$2
    local current_image_uuid=$(vmadm get $uuid | json image_uuid)
    local alias=$(vmadm get $uuid | json alias)

    # If we have a user-script for this zone/image here we must be doing a
    # rollback so we want to use that user-script. If we don't have one, we
    # save the current one for future rollback.
    mkdir -p user-scripts
    if [[ -f user-scripts/${alias}.${image_uuid}.user-script ]]; then
        NEW_USER_SCRIPT=user-scripts/${alias}.${image_uuid}.user-script
    else
        vmadm get ${uuid} | json customer_metadata."user-script" \
            > user-scripts/${alias}.${current_image_uuid}.user-script
        [[ -s user-scripts/${alias}.${current_image_uuid}.user-script ]] \
            || fatal "Failed to create ${alias}.${current_image_uuid}.user-script"

        if [[ -f /usbkey/default/user-script.common ]]; then
            NEW_USER_SCRIPT=/usbkey/default/user-script.common
        else
            fatal "Unable to find user-script for ${alias}"
        fi
    fi
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} | vmadm update ${uuid}

    # Update user-script for future provisions.
    mkdir -p sapi-updates
    local service_uuid=$(sdc-sapi /instances/${uuid} | json -H service_uuid)
    /usr/vm/sbin/add-userscript ${NEW_USER_SCRIPT} \
        | json -e "this.payload={metadata: this.set_customer_metadata}" payload \
        > sapi-updates/${service_uuid}.update
    sdc-sapi /services/${service_uuid} -X PUT -d @sapi-updates/${service_uuid}.update
}
