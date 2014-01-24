#!/usr/bin/bash
#
# rollback-ufds.sh: Rollback a UFDS just upgraded with upgrade-ufds.sh.
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
    for i in {1..60}; do
        sleep 2
        echo -n '.'
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
    for i in {1..60}; do
        sleep 2
        echo -n '.'
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



#---- mainline


# -- Gather info

if [[ $# -ne 1 ]]; then
    fatal "Usage: rollback-ufds.sh <rollback-images>"
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
UFDS_IMAGE=$(grep '^export UFDS_IMAGE' $1 | cut -d= -f2)
if [[ -z ${UFDS_IMAGE} ]]; then
    fatal "\$UFDS_IMAGE not defined"
fi
[[ $(hostname) == "headnode" ]] || fatal "not running on the headnode"

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
UFDS_SVC=$(sdc-sapi /services?name=ufds\&application_uuid=$SDC_APP | json -H 0.uuid)
[[ -n "$UFDS_SVC" ]] || fatal "could not determine sdc 'ufds' SAPI service"
UFDS_DOMAIN=$(bash /lib/sdc/config.sh -json | json ufds_domain)
[[ -n "$UFDS_DOMAIN" ]] || fatal "no 'ufds_domain' in sdc config"
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)

# Get the old zone. Assert we have exactly one on the HN.
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~ufds)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running ufdsN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)

# Make sure have the UFDS data to retore.
DUMP_PATH=moray_ufds_backup.sql
[[ -f "$DUMP_PATH" ]] || fatal "no UFDS data dump: '$DUMP_PATH' does not exist"

MANATEE_ZONE=$(vmadm lookup state=running owner_uuid=$UFDS_ADMIN_UUID tags.smartdc_role=manatee)
[[ -n "$MANATEE_ZONE" ]] || fatal "no manatee zone on the HN that we can use"
MORAY_ZONE=$(vmadm lookup alias=~moray | head -1)
[[ -n "$MORAY_ZONE" ]] || fatal "no moray zone on the HN that we can use"


# -- Do the UFDS upgrade.

# Rollback the ufds0 zone.
# WARNING: Presuming that ufds0 is the one to rollback.
[[ $CUR_ALIAS == "ufds0" ]] || fatal "current UFDS zone is not 'ufds0'"
empty=/var/tmp/empty
rm -f $empty
touch $empty
UFDS_IMAGE=$UFDS_IMAGE ./upgrade-all.sh -f $empty

# Restore the buckets.
# 1. disable ufds services
UFDS_FMRIS=$(svcs -z $CUR_UUID -a -Ho fmri | (grep ufds- || true))
echo "$UFDS_FMRIS" | xargs -n1 svcadm -z $CUR_UUID disable

# 2. drop the ufds buckets
DELBUCKET="/opt/smartdc/moray/build/node/bin/node /opt/smartdc/moray/node_modules/.bin/delbucket"
zlogin $MORAY_ZONE $DELBUCKET ufds_o_smartdc || true
zlogin $MORAY_ZONE $DELBUCKET ufds_cn_changelog || true

# 3. restart ufds services (ufds-master will create its buckets properly)
echo "$UFDS_FMRIS" | xargs -n1 svcadm -z $CUR_UUID enable
# Wait for buckets to be created.
echo "Wait up to a minute for ufds_o_smartdc bucket to be re-created."
GETBUCKET="/opt/smartdc/moray/build/node/bin/node /opt/smartdc/moray/node_modules/.bin/getbucket"
for i in {1..12}; do
    sleep 5
    echo -n '.'
    bucket=$( (zlogin $MORAY_ZONE $GETBUCKET ufds_o_smartdc 2>/dev/null || true) | json name )
    if [[ "$bucket" == "ufds_o_smartdc" ]]; then
        break
    fi
done
bucket=$( (zlogin $MORAY_ZONE $GETBUCKET ufds_o_smartdc 2>/dev/null || true) | json name )
if [[ "$bucket" != "ufds_o_smartdc" ]]; then
    fatal "'ufds_o_smartdc' bucket was not created by ufds-master after one minute"
fi



# Restore the UFDS data.
cp $DUMP_PATH /zones/$MANATEE_ZONE/root/var/tmp/moray_ufds_backup.sql
zlogin $MANATEE_ZONE "psql -U moray moray --command='DROP TABLE ufds_o_smartdc; DROP TABLE ufds_cn_changelog; DROP TABLE ufds_o_smartdc_locking_serial; DROP table ufds_cn_changelog_locking_serial; DROP SEQUENCE ufds_cn_changelog_serial; DROP SEQUENCE ufds_o_smartdc_serial;'"
zlogin $MANATEE_ZONE 'psql -U moray moray </var/tmp/moray_ufds_backup.sql'
