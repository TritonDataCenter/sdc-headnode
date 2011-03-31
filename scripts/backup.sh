#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#
# This script creates a backup of a headnode into a .tgz file and saves it into
# /opt/smartdc/backups. This .tgz can be used then to restore the backup either
# on the same physical machine or into a different headnode.
#
ERRORLOG="/tmp/perform_backup.$$.log"
BACKUPS="/opt/smartdc/backups"
BACKUP_VERSION=$(date -u +%Y%m%dT%H%M%SZ)
BACKUPDIR="${BACKUPS}/${BACKUP_VERSION}"

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
export PS4='+(${BASH_SOURCE}:${LINENO}): ${SECONDS} ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o errexit
set -o pipefail
set -o xtrace


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

function fatal
{
    msg=$1

    echo "--> FATAL: ${msg}"
    exit 1
}

function cleanup
{
    echo "==> Cleaning up"
    cd /
    rm -rf ${BACKUPDIR}

    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi

    echo "==> DONE!"
}

function on_error
{
    echo "--> FATAL: an error occurred, see ${ERRORLOG} for details."
    exit 1
}

function mount_usbkey
{
    if [[ -z $(mount | grep ^${usbmnt}) ]]; then
        echo "==> Mounting USB key"
        ${usbcpy}/scripts/mount-usb.sh
        mounted_usb="true"
    fi
}

function backup_usbkey
{
    backup_dir=${BACKUPDIR}

    mkdir -p ${backup_dir}/usbkey
    mkdir -p ${backup_dir}/zones

    echo "==> Creating backup in ${backup_dir}"

    # touch these, just to make sure they exist (in case of ancient build)
    # touch ${usbmnt}/datasets/smartos.uuid
    # touch ${usbmnt}/datasets/smartos.filename

    echo "==> Creating backup of USB key"

    (cd ${usbmnt} && gtar -cf - \
        boot/grub/menu.lst.tmpl \
        config \
        config.inc \
        data \
        datasets/smartos.{uuid,filename} \
        rc \
        scripts \
        ur-scripts \
        zoneinit \
        zones \
    ) \
    | (cd ${backup_dir}/usbkey && gtar --no-same-owner -xf -)
}

function backup_zones
{
    # dhcpd zone expects this to exist, so make sure it does:
    mkdir -p ${usbcpy}/os

    # Upgrade zones we can just recreate
    for zone in ${zones[@]}; do
        echo "==> Creating backup of zone '${zone}'"
        mkdir -p ${backup_dir}/zones/${zone}
        if [[ -x /zones/${zone}/root/opt/smartdc/bin/backup ]]; then
            /zones/${zone}/root/opt/smartdc/bin/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        elif [[ -x ${usbcpy}/zones/${zone}/backup ]]; then
            ${usbcpy}/zones/${zone}/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        else
            echo "--> Warning: No backup script for zone '${zone}'!"
        fi
    done
}

function create_backup_tarball
{
    cd ${BACKUPS}
    gtar -zcf ${BACKUP_VERSION}.tgz ${BACKUP_VERSION}
    rm -Rf ${BACKUPDIR}
}

# get ready to rock
mkdir -p ${BACKUPDIR}
trap cleanup EXIT
trap on_error ERR
echo "==> Logfile is ${ERRORLOG}"
echo "==> Running Backup Script"


mount_usbkey
backup_usbkey
trap cleanup EXIT

backup_zones
create_backup_tarball
# unset trap
trap - EXIT

exit 0
