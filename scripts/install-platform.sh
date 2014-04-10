#!/bin/bash
#
# Copyright 2013, Joyent Inc., All rights reserved.
#

function usage()
{
    echo "Usage: $0 [-cr -R|-s] <platform URI>"
    echo "(URI can be file:///, http://, anything curl supports or a filename)"
    exit 1
}

function fatal()
{
    printf "Error: %s\n" "$1" >/dev/stderr
    if [ ${fatal_cleanup} -eq 1 ]; then
        rm -rf ${usbmnt}/os/${version}
        rm -rf ${usbcpy}/os/${version}
        rm -f ${usbcpy}/os/tmp.$$.tgz
    fi
    exit 1
}

cleanup_key=0
do_reboot=0
switch_platform=0
force_replace=0
while getopts "cRrs" opt
do
    case "$opt" in
        c) cleanup_key=1;;
        r) do_reboot=1;;
        R) force_replace=1;;
        s) switch_platform=1;;
        *) usage;;
    esac
done
shift $(($OPTIND - 1))

input=$1
if [[ -z ${input} ]]; then
    usage
fi

if [ ${force_replace} -eq 1 -a ${switch_platform} -eq 1 ]; then
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

# BEGIN BASHSTYLED
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
# END BASHSTYLED
mounted="false"
fatal_cleanup=0

. /lib/sdc/config.sh
load_sdc_config

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

platform_type=smartos

# this should result in something like 20110318T170209Z
version=$(basename "${input}" .tgz | tr [:lower:] [:upper:] | \
          sed -e "s/.*\-\(2.*Z\)$/\1/")
if [[ -n $(echo $(basename "${input}") | \
    grep -i "HVM-${version}" 2>/dev/null) ]]; then
    version="HVM-${version}"
    platform_type=hvm
fi

echo "${version}" | grep "^2[0-9]*T[0-9]*Z$" > /dev/null
if [[ $? != 0 ]]; then
    echo "Invalid platform version format: ${version}" >&2
    echo "Please ensure this is a valid SmartOS platform image." >&2
    exit 1
fi

if [ ${force_replace} -eq 1 ]; then
    rm -rf ${usbmnt}/os/${version}
    rm -rf ${usbcpy}/os/${version}
fi

fatal_cleanup=1
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
fatal_cleanup=0

if [[ ${mounted} == "true" ]]; then
    echo "==> Unmounting USB Key"
    umount /mnt/usbkey
fi

echo "==> Adding to list of available platforms"

if [ ${switch_platform} -eq 1 ]; then
    echo "==> Switching boot image to ${version}"
    /usbkey/scripts/switch-platform.sh ${version}
    [ $? != 0 ] && fatal "switching boot image to ${version}"
fi

if [ ${cleanup_key} -eq 1 ]; then
    echo "==> Cleaning up key"
    /usbkey/scripts/cleanup-key.sh -c
    [ $? != 0 ] && fatal "cleaning key"
fi

if [ ${do_reboot} -eq 1 ]; then
    echo "==> Rebooting"
    reboot
fi

echo "==> Done!"

exit 0
