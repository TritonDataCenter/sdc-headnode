#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# upgrade-imgapi.sh:
#   - reprovision imgapi zone
#   - run imgapi migrations (SKIP_IMGAPI_MIGRATIONS=1 envvar to skip that)
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
    echo "Usage: upgrade-imgapi.sh upgrade-images"
    exit 1
fi

IMGAPI_IMAGE=$(source $1 >/dev/null; echo $IMGAPI_IMAGE)
if [[ -z ${IMGAPI_IMAGE} ]]; then
    fatal "\$IMGAPI_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

# Get the old imgapi zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json |json ufds_admin_uuid)
CURRENT_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~imgapi)
[[ -n "${CURRENT_UUID}" ]] \
    || fatal "there is not exactly one running imgapi zone";
CURRENT_ALIAS=$(vmadm get $CURRENT_UUID | json alias)
CURRENT_IMAGE=$(vmadm get $CURRENT_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CURRENT_IMAGE == $IMGAPI_IMAGE ]]; then
    echo "$0: already using image $CURRENT_IMAGE for zone $CURRENT_UUID ($CURRENT_ALIAS)"
    exit 0
fi


# Bail if the imgapi zone is so old it doesn't have a delegate dataset.
num_imgapi_datasets=$(vmadm get $CURRENT_UUID | json datasets.length)
if [[ "$num_imgapi_datasets" != 1 ]]; then
    fatal "Current imgapi zone ($CURRENT_UUID) has no delegate dataset. Upgrading it would loose image file data!"
fi


empty=/var/tmp/empty
rm -f $empty
touch $empty
REALLY_UPGRADE_IMGAPI=1 IMGAPI_ALIAS=$CURRENT_ALIAS IMGAPI_IMAGE=$IMGAPI_IMAGE ./upgrade-all.sh $empty


# "SKIP_IMGAPI_MIGRATIONS" is to allow rollback-imgapi.sh to use this script.
if [[ -z "$SKIP_IMGAPI_MIGRATIONS" ]]; then
    # At the time of writing we are pretty sure we only need to worry about
    # imgapi's in the field need migrations from 006 and up.
    # TODO: tie this to imgapi versions appropriately.
    echo ''
    echo '* * *'
    echo 'Run imgapi migrations.'
    echo '* * *'
    echo ''
    zlogin $CURRENT_UUID svcadm disable imgapi
# Per discussion on mib@ for the CM-172 update, accidentally left
# sdcimage entries in UFDS can make upgrading a pain: potentially
# requires clean up of bogus image entries. We now presume
# all SDC installs are past the IMGAPI change needing migration-007.
#    echo 'migration-006-cleanup-manta-storage.js'
#    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-006-cleanup-manta-storage.js'
#    echo ''
#    echo 'migration-007-ufds-to-moray.js'
#    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-007-ufds-to-moray.js'
    echo ''
    echo 'migration-008-new-storage-layout.js'
    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-008-new-storage-layout.js'
    echo ''
    echo 'migration-009-backfill-archive.js'
    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-009-backfill-archive.js'
    echo ''
    echo 'migration-010-backfill-billing_tags.js'
    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-010-backfill-billing_tags.js'
    echo ''
    echo 'migration-011-backfill-published_at.js'
    zlogin $CURRENT_UUID 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-011-backfill-published_at.js'
    zlogin $CURRENT_UUID svcadm enable imgapi
fi


echo 'Done imgapi upgrade.'
