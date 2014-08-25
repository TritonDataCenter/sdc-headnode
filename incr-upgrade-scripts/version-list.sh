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
# version-list.sh: list image uuids and corresponding git shas of
# deployed images.
#
# Limitations:
# - This process can't handle multiple instances (e.g. two morays on beta-4)
# - Presumes all core zones are on the HN.
#


if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}

function warn
{
    echo "$0: warn: $*" >&2
}


ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
corezones=$(sdc-vmapi /vms?owner_uuid=$ufds_admin_uuid\&state=running \
    | json -H -c 'this.tags && this.tags.smartdc_role' -e 'this.role=this.tags.smartdc_role')
for line in $(echo "$corezones" | json -a role alias uuid image_uuid -d: | sort); do
    role=$(echo "$line" | cut -d: -f1)
    alias=$(echo "$line" | cut -d: -f2)
    image_uuid=$(echo "$line" | cut -d: -f4)
    echo $alias >&2
    stamp=$((sdc-imgadm get $image_uuid || true) | json version)
    if [[ -z "$stamp" ]]; then
        stamp="(not found in imgapi)"
    fi
    echo "export $(echo $role | tr 'a-z' 'A-Z')_IMAGE=$image_uuid    # alias=$alias, stamp=$stamp"
done
