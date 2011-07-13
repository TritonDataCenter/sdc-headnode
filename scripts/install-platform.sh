#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

set -o errexit
set -o pipefail
#set -o xtrace

function usage()
{
    echo "Usage: $0 <platform URI>"
    echo "(URI can be file:///, http://, anything curl supports or a filename)"
    exit 1
}

input=$1
if [[ -z ${input} ]]; then
    usage
fi

if echo "${input}" | grep "^[a-z]*://"; then
    # input is a url style pattern
    /bin/true
else
    if [[ -f ${input} ]]; then
       dir=$(cd $(dirname ${input}); pwd)
       file=$(basename ${input})
       input="file://${dir}/${file}"
    else
       echo "File: '${input}' not found."
       usage
    fi
fi

mounted="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

. /lib/sdc/config.sh
load_sdc_config

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

# this should result in something like 20110318T170209Z
version=$(basename "${input}" .tgz | tr [:lower:] [:upper:] | sed -e "s/.*\-\(2.*Z\)$/\1/")
if [[ -n $(echo $(basename "${input}") | grep -i "HVM-${version}" 2>/dev/null) ]]; then
    version="HVM-${version}"
fi

if [[ ! -d ${usbmnt}/os/${version} ]]; then
    echo "==> Unpacking ${version} to ${usbmnt}/os"
    curl --progress -k ${input} \
        | (mkdir -p ${usbmnt}/os/${version} \
        && cd ${usbmnt}/os/${version} \
        && gunzip | tar -xf - 2>/tmp/install_platform.log \
        && mv platform-* platform
    )

    if [[ -f ${usbmnt}/os/${version}/platform/root.password ]]; then
         mv -f ${usbmnt}/os/${version}/platform/root.password \
             ${usbmnt}/private/root.password.${version}
    fi
fi

if [[ ! -d ${usbcpy}/os/${version} ]]; then
    echo "==> Copying ${version} to ${usbcpy}/os"
    mkdir -p ${usbcpy}/os
    (cd ${usbmnt}/os && rsync -a ${version}/ ${usbcpy}/os/${version})
fi

if [[ ${mounted} == "true" ]]; then
    echo "==> Unmounting USB Key"
    umount /mnt/usbkey
fi

echo "==> Adding to list of available platforms"

# Wait until MAPI is actually up. Attempts to guarantee that (watching the MAPI svc)
# before calling this script aren't reliable.
mapi_ping="curl -f --connect-timeout 2 -u ${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw} --url http://${CONFIG_mapi_admin_ip}/"
for i in {1..12}; do
    if [[ `${mapi_ping} >/dev/null 2>&1; echo $?` == "0" ]]; then
        break
    fi
    sleep 5
done
if [[ `${mapi_ping} >/dev/null 2>&1; echo $?` != "0" ]]; then
    echo "FAILED waiting for MAPI to come up, can't update."
    exit 1
fi

curr_list=$(curl -s -f -u "${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw}" \
    --url http://${CONFIG_mapi_admin_ip}/admin/platform_images 2>/dev/null || /bin/true)
if [[ $? -eq 0 ]]; then
    # MAPI returned empty content for "no platform images".
    [[ -z "${curr_list}" ]] && curr_list='[]'

    elements=$(echo "${curr_list}" | json length)
    found="false"
    idx=0
    while [[ ${found} == "false" && ${idx} -lt ${elements} ]]; do
        name=$(echo "${curr_list}" | json ${idx}.name)
        if [[ -n ${version} && ${name} == ${version} ]]; then
            found="true"
        fi
        idx=$(($idx + 1))
    done

    if [[ -n ${version} && ${found} != "true" ]]; then
        if ! curl -s -f \
            -X POST \
            -u "${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw}" \
            --url http://${CONFIG_mapi_admin_ip}/admin/platform_images \
            -H "Accept: application/json" \
            -d platform_type="hvm" \
            -d name=${version} >/dev/null 2>&1; then

            echo "==> FAILED to add to list of platforms, you'll need to update manually"
        else
            echo "==> Added ${version} to MAPI's list"
        fi
    fi

else
    echo "FAILED to get current list of platforms, can't update."
fi

echo "==> Done!"

exit 0
