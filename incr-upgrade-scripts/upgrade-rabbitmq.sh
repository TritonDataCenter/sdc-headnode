#!/usr/bin/bash
#
# upgrade-rabbitmq.sh:
#   - reprovision rabbitmq0 zone
#   - sdc-agent-healthcheck
#
# It is suggested this is gated by:
#   ./dc-maint-start.sh
#   ...
#   ./dc-maint-end.sh
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

if [[ $# -ne 1 ]]; then
    echo "Usage: upgrade-rabbitmq.sh upgrade-images"
    exit 1
fi

RABBITMQ_IMAGE=$(grep '^export RABBITMQ_IMAGE' $1 | tail -1 | cut -d'=' -f2 | awk '{print $1}')
if [[ -z ${RABBITMQ_IMAGE} ]]; then
    fatal "\$RABBITMQ_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old rabbitmq zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json |json ufds_admin_uuid)
CURRENT_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~rabbitmq)
[[ -n "${CURRENT_UUID}" ]] \
    || fatal "there is not exactly one running rabbitmqN zone";
CURRENT_ALIAS=$(vmadm get $CURRENT_UUID | json alias)
CURRENT_IMAGE=$(vmadm get $CURRENT_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CURRENT_IMAGE == $RABBITMQ_IMAGE ]]; then
    echo "$0: already using image $CURRENT_IMAGE for zone $CURRENT_UUID ($CURRENT_ALIAS)"
    exit 0
fi

empty=/var/tmp/empty
rm -f $empty
touch $empty
REALLY_UPGRADE_RABBITMQ=1 RABBITMQ_IMAGE=$RABBITMQ_IMAGE ./upgrade-all.sh $empty

echo ''
echo '* * *'
echo 'Wait 30s (sleeps are lame) before running agent healthcheck.'
sleep 30
echo 'Check agent health after rabbit upgrade (full log to agent-healthcheck.log):'
bash sdc-agent-healthcheck.sh | tee agent-healthcheck.log | grep error || echo "(no errors)"
echo '* * *'

echo 'Done rabbitmq upgrade.'

