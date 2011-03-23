#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

#set -o xtrace

ROOT=/var/tmp/upgrade

RECREATE_ZONES=( \
    assets \
    atropos \
    ca \
    dhcpd \
    portal \
    rabbitmq \
)

# Upgrade the usbkey itself
# TODO:
#   - Mount the usb key
#   - Untar the file from ${ROOT}/usbkey/ to /mnt/usbkey
#   - proper rsync from /mnt/usbkey to /usbkey

# XXX need to pull out packages from atropos zone before recreating and republish after!

# Upgrade zones we can just recreate
for zone in "${RECREATE_ZONES[@]}"; do
    /usbkey/scripts/destroy-zone.sh ${zone}
    /usbkey/scripts/create-zone.sh ${zone}
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
# if there are agents in ${ROOT}/agents, publish to npm (and apply?)

exit 0
