#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#
# This script restores a backup of a headnode from a .tgz file.
# This .tgz can be used then to restore the backup either
# on the same physical machine or into a different headnode.
#
ERRORLOG="/tmp/perform_restore.$$.log"
TEMPDIR="/var/tmp/restore.$$"

#
# This is a fancy way of saying, send:
#
#  - a copy of stdout
#  - a copy of stderr
#  - xtrace output
#
# to the log file.
#
rm -f ${ERRORLOG}
exec > >(tee -a ${ERRORLOG}) 2>&1
exec 4>>${ERRORLOG}
BASH_XTRACEFD=4
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o errexit
set -o pipefail
set -o xtrace

function fatal
{
    msg=$1

    echo "--> FATAL: ${msg}"
    exit 1
}

function on_error
{
    echo "--> FATAL: an error occurred, see ${ERRORLOG} for details."
    exit 1
}

mounted_usb="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
zones=$(ls ${usbcpy}/zones)

. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

# Ensure we're a SmartOS headnode
if [[ ${SYSINFO_Bootparam_headnode} != "true" \
    || $(uname -s) != "SunOS" \
    || -z ${SYSINFO_Live_Image} ]]; then

    fatal "this can only be run on a SmartOS headnode."
fi



function cleanup
{
    echo "==> Cleaning up"
    cd /
    rm -rf ${TEMPDIR}

    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi

    echo "==> DONE!"
}

function mount_usbkey
{
    if [[ -z $(mount | grep ^${usbmnt}) ]]; then
        echo "==> Mounting USB key"
        ${usbcpy}/scripts/mount-usb.sh
        mounted_usb="true"
    fi
}

#function restore_usbkey
#{
#     backupdir=$1
#}

function restore_zones
{
    backup_dir=$1
    for zone in ${zones[@]}; do
        echo "==> Restoring backup of zone '${zone}'"
        if [[ -x /zones/${zone}/root/opt/smartdc/bin/restore ]]; then
            cp /zones/${zone}/root/opt/smartdc/bin/restore /tmp/restore$$
            /tmp/restore$$ ${zone} ${backup_dir}/zones/${zone}/
            rm -f /tmp/restore$$
        elif [[ -x ${usbcpy}/zones/${zone}/restore ]]; then
            ${usbcpy}/zones/${zone}/restore ${zone} \
                ${backup_dir}/zones/${zone}/
        else
            echo "--> Warning: No restore script for zone '${zone}'!"
        fi
    done
}


input=$1
if [[ -z ${input} || ! -f ${input} ]]; then
    sleep 0.1 # since output is going through tee and might lag slightly
    echo "Usage: $0 <restore file>"
    exit 1
fi

# get ready to rock
mkdir -p ${TEMPDIR}
trap cleanup EXIT
trap on_error ERR
echo "==> Logfile is ${ERRORLOG}"

# unpack restore file to and go to the temp dir
echo "==> Unpacking ${input} to ${TEMPDIR}"
gzcat ${input} | (cd ${TEMPDIR} && tar -xf -)
cd ${TEMPDIR}
BACKUPDIR=$(basename ${input%.*})
echo ${BACKUPDIR}
cd ${BACKUPDIR}

if [[ ! -d "${TEMPDIR}/${BACKUPDIR}/usbkey" ]]; then
    echo "--> FATAL: ${TEMPDIR}/${BACKUPDIR} contains no 'usbkey' directory.  Aborting!"
    exit 1
fi

if [[ ! -d "${TEMPDIR}/${BACKUPDIR}/zones" ]]; then
    echo "--> FATAL: ${TEMPDIR}/${BACKUPDIR} contains no 'zones' directory.  Aborting!"
    exit 1
fi

mount_usbkey
#restore_usbkey "${TEMPDIR}/${BACKUPDIR}"
trap cleanup EXIT

restore_zones "${TEMPDIR}/${BACKUPDIR}"

# unset trap
trap - EXIT
cleanup

exit 0
