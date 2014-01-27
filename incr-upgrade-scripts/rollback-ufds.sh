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



#---- mainline

# -- Gather info

if [[ $# -ne 1 ]]; then
    fatal "Usage: rollback-ufds.sh <rollback-images>"
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
UFDS_IMAGE=$(grep '^export UFDS_IMAGE' $1 | tail -1 | cut -d= -f2 | awk '{print $1}')
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
REALLY_UPGRADE_UFDS=1 UFDS_IMAGE=$UFDS_IMAGE ./upgrade-all.sh -f $empty

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
