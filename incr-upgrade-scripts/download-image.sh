#!/usr/bin/bash
#
# download-image.sh: download and install an image from updates.joyent.com
#

set -o xtrace
set -o errexit

fatal()
{
    echo "Error: $1"
    exit 1
}

[[ $# -eq 1 ]] || fatal "usage: $0 <image uuid>"

REMOTE='/opt/smartdc/bin/updates-imgadm'
LOCAL='/opt/smartdc/bin/sdc-imgadm'

UUID=$1

manifest=/var/tmp/${UUID}.manifest
file=/var/tmp/${UUID}.file

set +o errexit
${LOCAL} get ${UUID} >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "Image ${UUID} already installed."
    exit 0
fi

${REMOTE} get $UUID > ${manifest} || fatal "failed to get image manifest"

bytes=$(json -f ${manifest} files.0.size)
printf "Downloading image $UUID (%d MiB) ... " $(( ${bytes} / 1024 / 1024 ))

${REMOTE} get-file $UUID > ${file} || fatal "failed to get image file"

echo "done!"

ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
json -f $manifest -e "this.owner = '$ufds_admin_uuid'" > $manifest.tmp
mv $manifest.tmp $manifest

${LOCAL} import -m ${manifest} -f ${file} || fatal "failed to import image ${UUID}"

set +o errexit
imgadm get ${image_uuid} >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    uuid=$(json -f ${manifest} uuid)
    imgadm import ${uuid} || fatal "failed to install image"
fi
set -o errexit

rm -f ${manifest} ${file}

exit 0
