#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

BASH_XTRACEFD=4
set -o xtrace

ROOT=$(pwd)

RECREATE_ZONES=( \
    assets \
    atropos \
    ca \
    dhcpd \
    portal \
    rabbitmq \
)

mounted_usb="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

# TODO ensure we're a SmartOS headnode

# Upgrade the usbkey itself
#   - Mount the usb key
#   - Untar the file from ${ROOT}/usbkey/ to /mnt/usbkey
#   - proper rsync from /mnt/usbkey to /usbkey

function cleanup
{
    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi
}

usbupdate=$(ls ${ROOT}/usbkey/*.tgz | tail -1)
if [[ -n ${usbupdate} ]]; then
    if [[ -z $(mount | grep ^${usbmnt}) ]]; then
        echo "==> Mounting USB key"
        ${usbcpy}/scripts/mount-usb.sh
        mounted_usb="true"
    fi
    (cd ${usbmnt} && gzcat ${usbupdate} | tar -xvf -)

    # XXX (this is the point where we'd fix the config in /mnt/usbkey/config)
    (cd ${usbmnt} && rsync -a --exclude private --exclude os * ${usbcpy})
fi

trap cleanup EXIT

# XXX need to pull out packages from atropos zone before recreating and republish after!

# Upgrade zones we can just recreate
for zone in "${RECREATE_ZONES[@]}"; do
    ${usbcpy}/scripts/destroy-zone.sh ${zone}
    ${usbcpy}/scripts/create-zone.sh ${zone}
done

# Upgrade zones that use app-release-builder
if [[ -d ${ROOT}/zones ]]; then
    cd ${ROOT}/zones
    for file in `ls *.tbz2`; do
	    tar -jxf ${file}
    done
    for dir in `ls`; do
	if [[ -d ${dir} ]]; then
	    (cd ${dir} && ./*-dataset-update.sh)
        fi
    done
fi

# TODO
#
# If there are agents in ${ROOT}/agents, publish to npm (and apply?)
# If not (default) MAPI will have updated for us
#

exit 0
