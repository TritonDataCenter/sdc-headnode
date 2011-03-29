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

. /lib/sdc/config.sh
load_sdc_sysinfo

# Ensure we're a SmartOS headnode
if [[ ${SYSINFO_Bootparam_headnode} != "true" \
    || $(uname -s) != "SunOS" \
    || -z ${SYSINFO_Live_Image} ]]; then

    echo "This can only be run on a SmartOS headnode."
    exit 1
fi

# TODO: check system / version to ensure it's possible to apply this update.

function cleanup
{
    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi
}

function upgrade_usbkey
{
    # TODO: need to do backup of this stuff before blowing away.

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
}

function recreate_zones
{
    # TODO: need to pull out packages from atropos zone before recreating and republish after!
    # TODO: backup zones.

    # Upgrade zones we can just recreate
    for zone in "${RECREATE_ZONES[@]}"; do
        ${usbcpy}/scripts/destroy-zone.sh ${zone}
        ${usbcpy}/scripts/create-zone.sh ${zone} -w
    done

    # Make sure we set the npm user correctly for the atropos registry, since the
    # atropos zone may have been recreated.
    if [[ -x /opt/smartdc/agents/bin/setup-npm-user ]]; then
        /opt/smartdc/agents/bin/setup-npm-user joyent joyent atropos@joyent.com
    fi
}

function upgrade_zones
{
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
}

function install_platform
{
    # Install new platform
    platformupdate=$(ls ${ROOT}/platform/platform-*.tgz | tail -1)
    if [[ -n ${platformupdate} && -f ${platformupdate} ]]; then
        platformversion=$(basename "${platformupdate}" | sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")

        if [[ -z ${platformversion} || ! -d ${usbcpy}/os/${platformversion} ]]; then
            ${usbcpy}/scripts/install-platform.sh file://${platformupdate}
        else
            echo "INFO: ${usbcpy}/os/${version} already exists, skipping update."
        fi
    fi
}

function reenable_agents
{
    oldifs=$IFS
    IFS=$'\n'

    for line in $(svcs -Ho STA,FMRI smartdc/agent/* | tr -s ' '); do
        state=${line%% *}
        fmri=${line#* }

        if [[ ${state} == "MNT" ]]; then
            svcadm disable -s ${fmri}
            svcadm enable -s ${fmri}
        fi

    done

    IFS=${oldifs}
}

# TODO:
#  verify upgrade can work on this machine (ie. we're already running the correct version)


upgrade_usbkey
trap cleanup EXIT
recreate_zones
upgrade_zones
reenable_agents

# TODO
#
# If there are agents in ${ROOT}/agents, publish to npm (and apply?)
# If not (default) MAPI will have updated for us
#

install_platform

# TODO: update version

exit 0
