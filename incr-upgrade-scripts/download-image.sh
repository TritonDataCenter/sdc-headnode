#!/usr/bin/bash
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

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh

UPDATES_IMGADM='/opt/smartdc/bin/updates-imgadm'
SDC_IMGADM='/opt/smartdc/bin/sdc-imgadm'


#---- support routines

function import_image() {
    local uuid=$1
    local manifest=/var/tmp/${uuid}.manifest.$$
    local file=/var/tmp/${uuid}.file.$$

    set +o errexit
    if [[ -n "$(${SDC_IMGADM} get ${uuid} 2>/dev/null || true)" ]]; then
        echo "Image ${uuid} already installed."
        return
    fi

    ${UPDATES_IMGADM} get $uuid >${manifest} \
        || fatal "failed to get image $uuid manifest"
    local origin=$(json -f $manifest origin)
    if [[ -n "$origin" ]]; then
        echo "Import origin image $origin"
        import_image $origin
    fi

    bytes=$(json -f ${manifest} files.0.size)
    name=$(json -f ${manifest} name)
    version=$(json -f ${manifest} version)
    printf "Downloading image $uuid ($name $version) file (%d MiB).\n" \
        $(( ${bytes} / 1024 / 1024 ))
    ${UPDATES_IMGADM} get-file $uuid > ${file} \
        || fatal "failed to get image $uuid file from updates.joyent.com"

    ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
    json -f $manifest -e "this.owner = '$ufds_admin_uuid'" > $manifest.tmp
    mv $manifest.tmp $manifest

    ${SDC_IMGADM} import -m ${manifest} -f ${file} \
        || fatal "failed to import image ${uuid}"

    if [[ -z "$(imgadm get $uuid 2>/dev/null)" ]]; then
        imgadm import ${uuid} || fatal "failed to install image $uuid into zpool"
    fi

    rm -f ${manifest} ${file}
}




#---- mainline

[[ $# -eq 1 ]] || fatal "usage: $0 <image uuid>"
import_image $1
exit 0
