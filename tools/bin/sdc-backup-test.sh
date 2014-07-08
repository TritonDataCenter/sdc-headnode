#!/usr/bin/bash

#
# Copyright (c) 2014, Joyent, Inc. All rights reserved.
# This is used to copy a "restore" image over a usbkey image, intended for
# testing only.
#

unset LD_LIBRARY_PATH
PATH=/usr/bin:/usr/sbin:/opt/smartdc/bin
export PATH

# This writes xtrace output and anything redirected to LOGFD to the log file.
LOGFD=4
exec 4>/tmp/backuplog.$$
# BASHSTYLED
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=${LOGFD}
set -o xtrace
set -o pipefail
set -o errexit

echo "logs at /tmp/backuplog.$$"

readonly backup_image=$1
readonly backup_mnt=/mnt/backup-usbkey
CLEANED=0

function cleanup
{
    local USB_MOUNTED=
    USBKEY_MOUNTED=$(mount | grep '/mnt/usbkey' || true)
    [[ -n ${USBKEY_MOUNTED} ]] && pfexec umount /mnt/usbkey

    if [[ ${LOOPBACK} ]]; then
        pfexec umount ${backup_mnt}
        pfexec lofiadm -d ${LOOPBACK}
    fi
    sync; sync
    LOOPBACK=
}

function mount_images
{
    local USB_MOUNTED=
    USBKEY_MOUNTED=$(mount | grep '/mnt/usbkey' || true)
    [[ -z ${USBKEY_MOUNTED} ]] && /usbkey/scripts/mount-usb.sh

    LOOPBACK=$(pfexec lofiadm -a ${backup_image})
    # XXX - /usbkey/scripts uses noatime here?
    pfexec mount -F pcfs -o foldcase ${LOOPBACK}:c ${backup_mnt}
}

function copy_image
{
    # XXX - brute force.
    echo "This might take a while."
    rm -rf /mnt/usbkey
    cp -r ${backup_mnt} /mnt/usbkey
}

if [[ $(sysinfo | json '["Boot Parameters"].headnode') != "true" ]]
then
    fatal "can only be run from the headnode"
fi

trap cleanup EXIT

mount_images
copy_image_to_usbkey
cleanup
