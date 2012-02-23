#!/bin/bash
#
# Copyright (c) 2012, Joyent Inc., All rights reserved.
#

function usage()
{
    echo "Usage: $0 <platform URI>"
    echo "(URI can be file:///, http://, anything curl supports or a filename)"
    exit 1
}

function fatal()
{
	printf "Error: %s\n" "$1" >/dev/stderr
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
       fatal "file: '${input}' not found."
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

platform_type=smartos

# this should result in something like 20110318T170209Z
version=$(basename "${input}" .tgz | tr [:lower:] [:upper:] | sed -e "s/.*\-\(2.*Z\)$/\1/")
if [[ -n $(echo $(basename "${input}") | grep -i "HVM-${version}" 2>/dev/null) ]]; then
    version="HVM-${version}"
    platform_type=hvm
fi

if [[ ! -d ${usbmnt}/os/${version} ]]; then
    echo "==> Staging ${version}"
    curl --progress -k ${input} -o ${usbcpy}/os/tmp.$$.tgz
    [ $? != 0 ] && fatal "retrieving $input"

    [[ ! -f ${usbcpy}/os/tmp.$$.tgz ]] && fatal "file: '${input}' not found."
    
    echo "==> Unpacking ${version} to ${usbmnt}/os"
    echo "==> This may take a while..."
    mkdir -p ${usbmnt}/os/${version}
    [ $? != 0 ] && fatal "unable to mkdir ${usbmnt}/os/${version}"
    (cd ${usbmnt}/os/${version} \
      && gzcat ${usbcpy}/os/tmp.$$.tgz | tar -xf - 2>/tmp/install_platform.log)
    [ $? != 0 ] && fatal "unpacking image into ${usbmnt}/os/${version}"

    (cd ${usbmnt}/os/${version} && mv platform-* platform)
    [ $? != 0 ] && fatal "moving image in ${usbmnt}/os/${version}"

    rm -f ${usbcpy}/os/tmp.$$.tgz

    if [[ -f ${usbmnt}/os/${version}/platform/root.password ]]; then
         mv -f ${usbmnt}/os/${version}/platform/root.password \
             ${usbmnt}/private/root.password.${version}
    fi
fi

if [[ ! -d ${usbcpy}/os/${version} ]]; then
    echo "==> Copying ${version} to ${usbcpy}/os"
    mkdir -p ${usbcpy}/os
    [ $? != 0 ] && fatal "mkdir ${usbcpy}/os"
    (cd ${usbmnt}/os && rsync -a ${version}/ ${usbcpy}/os/${version})
    [ $? != 0 ] && fatal "copying image to ${usbmnt}/os"
fi

if [[ ${mounted} == "true" ]]; then
    echo "==> Unmounting USB Key"
    umount /mnt/usbkey
fi

echo "==> Adding to list of available platforms"

# Wait until MAPI is actually up. Attempts to guarantee that (watching the MAPI
# svc) before calling this script aren't reliable.

mapi_ping="curl -f --connect-timeout 2 -u ${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw} --url http://${CONFIG_mapi_admin_ip}/"
for i in {1..12}; do
    if [[ `${mapi_ping} >/dev/null 2>&1; echo $?` == "0" ]]; then
        break
    fi
    sleep 5
done
[[ `${mapi_ping} >/dev/null 2>&1; echo $?` != "0" ]] && \
    fatal "FAILED waiting for MAPI to come up, can't update."

curr_list=$(curl -s -f \
    -u "${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw}" \
    --url http://${CONFIG_mapi_admin_ip}/admin/platform_images 2>/dev/null)

[[ $? != 0 ]] && fatal "FAILED to get current list of platforms, can't update."

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
        -d platform_type=${platform_type} \
        -d name=${version} >/dev/null 2>&1; then

        fatal \
        "==> FAILED to add to list of platforms, you'll need to update manually"
    else
        echo "==> Added ${version} to MAPI's list"
    fi
fi

echo "==> Done!"

exit 0
