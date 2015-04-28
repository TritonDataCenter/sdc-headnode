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
# download-image.sh: download and install an image from updates.joyent.com
#
# Note: We *should* just be using:
#       sdc-imgadm import UUID -S https://updates.joyent.com
# but we don't because we still haven't cleaned up 'owner' field handling in
# images from public/private repos (e.g. from updates.joyent.com) where there
# is no meaning user database, or at least meaningfully shareable user
# database with the local DC.
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}

function import_image() {
    local uuid=$1
    local manifest=/var/tmp/${uuid}.manifest.$$
    local file=$2
    if [[ -z $file ]]; then
        file=/var/tmp/${uuid}.file.$$
    fi

    SDC_IMGADM='/opt/smartdc/bin/sdc-imgadm'

    set +o errexit
    if [[ -n "$(${SDC_IMGADM} get ${uuid} 2>/dev/null || true)" ]]; then
        echo "Image ${uuid} already installed."
        return
    fi

    # Avoid using 'updates-imgadm' because really old ones don't know about
    # updates.joyent.com channels and we want to get this image UUID out of
    # whatever channel it is in.
    #
    # Use API version 2 to get 'channels' field that we need below.
    curl -ksSf https://updates.joyent.com/images/$uuid?channel=* \
        -H 'Accept-Version: ~2' \
        >${manifest} \
        || fatal "failed to get image $uuid manifest"
    local origin=$(json -f $manifest origin)
    if [[ -n "$origin" ]]; then
        echo "Import origin image $origin"
        import_image $origin
    fi

    bytes=$(json -f ${manifest} files.0.size)
    name=$(json -f ${manifest} name)
    version=$(json -f ${manifest} version)

    if [[ -e $file ]]; then
        local fsize=$(stat -c%s "$file")
        if [[ $fsize != $bytes ]]; then
            fatal "$file size mismatch: Manifest size $bytes, File size $fsize"
        fi
    else
        printf "Downloading image $uuid ($name $version) file (%d MiB).\n" \
            $(( ${bytes} / 1024 / 1024 ))
        # Need to be specific on a channel for this endpoint.
        local channel=$(json -f $manifest channels.0)
        curl -ksSf https://updates.joyent.com/images/$uuid/file?channel=$channel >${file} \
            || fatal "failed to get image $uuid file from updates.joyent.com"
    fi

    # Manifest tweaks for compat:
    # - Set owner to the admin UUID to workaround older versions that don't
    #   support the all-zero's owner work.
    # - Remove 'channels' for the case of an upgraded 'updates-imgadm'
    #   (i.e. we ran upgrade-tools.sh), but an IMGAPI pre-channels work.
    ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
    json -f $manifest \
        -e "this.owner = '$ufds_admin_uuid'" \
        -e "this.channels = undefined" \
        > $manifest.tmp
    mv $manifest.tmp $manifest

    ${SDC_IMGADM} import -m ${manifest} -f ${file} \
        || fatal "failed to import image ${uuid}"

    if [[ -z "$(imgadm get $uuid 2>/dev/null)" ]]; then
        imgadm import ${uuid} || fatal "failed to install image $uuid into zpool"
    fi

    rm -f ${manifest} ${file}
}




#---- mainline

[[ $# -gt 0 ]] || fatal "usage: $0 <image uuid> [image file]"
import_image $1 $2
exit 0
