#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#
# SUMMARY
#
# This is an example upgrade.sh script which shows how one will be built for an
# actual SDC upgrade.
#

BASH_XTRACEFD=4
set -o xtrace

ROOT=$(pwd)
export SDC_UPGRADE_ROOT=${ROOT}

#
# IMPORTANT, this purposefully does not include 'portal' since that zone
# is handled differently for upgrades (since it may be customized).
#
RECREATE_ZONES=( \
    assets \
    atropos \
    ca \
    dhcpd \
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
    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi
}

function mount_usbkey
{
    if [[ -z $(mount | grep ^${usbmnt}) ]]; then
        echo "==> Mounting USB key"
        ${usbcpy}/scripts/mount-usb.sh
        mounted_usb="true"
    fi
}

function check_versions
{
    new_version=$(cat ${ROOT}/VERSION)

    existing_version=$(cat ${usbmnt}/version 2>/dev/null)
    if [[ -z ${existing_version} ]]; then
        echo "--> Warning: unable to find version file in ${usbmnt}, assuming build is ancient."
        existing_version="ancient"
    fi

    # TODO: check system / version to ensure it's possible to apply this update.
    #
    # This needs to be filled in manually as part of an actual SDC upgrade.

    echo "==> Upgrading from ${existing_version} to ${new_version}"
}

function backup_usbkey
{
    backup_dir=${usbcpy}/backup/${existing_version}.$(date -u +%Y%m%dT%H%M%SZ)

    if [[ -d ${backup_dir} ]]; then
        fatal "unable to create back dir ${backup_dir}"
    fi
    mkdir -p ${backup_dir}/usbkey
    mkdir -p ${backup_dir}/zones

    echo "==> Creating backup in ${backup_dir}"

    # touch these, just to make sure they exist (in case of ancient build)
    touch ${usbmnt}/datasets/smartos.uuid
    touch ${usbmnt}/datasets/smartos.filename

    (cd ${usbmnt} && gtar -cf - \
        boot/grub/menu.lst.tmpl \
        datasets/smartos.{uuid,filename} \
        rc \
        scripts \
        ur-scripts \
        zoneinit \
        zones \
    ) \
    | (cd ${backup_dir}/usbkey && gtar --no-same-owner -xf -)
}

function upgrade_usbkey
{
    usbupdate=$(ls ${ROOT}/usbkey/*.tgz | tail -1)
    if [[ -n ${usbupdate} ]]; then
        (cd ${usbmnt} && gzcat ${usbupdate} | gtar --no-same-owner -xf -)

        # XXX (this is the point where we'd fix the config in /mnt/usbkey/config)
        (cd ${usbmnt} && rsync -a --exclude private --exclude os * ${usbcpy})
    fi
}

function import_datasets
{
    ds_uuid=$(cat ${usbmnt}/datasets/smartos.uuid)
    ds_file=$(cat ${usbmnt}/datasets/smartos.filename)

    if [[ -z ${ds_uuid} ]]; then
        fatal "no uuid set in ${usbmnt}/datasets/smartos.uuid"
    else
        echo "==> Ensuring ${ds_uuid} is imported."
        if [[ -z $(zfs list | grep "^zones/e2abe3f6-5668-11e0-bab1-07a4d450d804") ]]; then
            # not already imported
            if [[ -f ${usbmnt}/datasets/${ds_file} ]]; then
                bzcat ${usbmnt}/datasets/${ds_file} \
                    | zfs recv zones/${ds_uuid} \
                    || fatal "unable to import ${ds_uuid}"
            else
                fatal "unable to import ${ds_uuid} (${ds_file} doesn't exist)"
            fi
        fi
    fi
}

function recreate_zones
{
    # TODO: need to pull out packages from atropos zone before recreating and republish after!

    # Upgrade zones we can just recreate
    for zone in "${RECREATE_ZONES[@]}"; do
        mkdir -p ${backup_dir}/zones/${zone}
        /zones/${zone}/root/opt/smartdc/bin/backup ${zone} \
            ${backup_dir}/zones/${zone}/
        ${usbcpy}/scripts/destroy-zone.sh ${zone}
        ${usbcpy}/scripts/create-zone.sh ${zone} -w
    done

    # Make sure we set the npm user correctly for the atropos registry, since the
    # atropos zone may have been recreated.
    if [[ -x /opt/smartdc/agents/bin/setup-npm-user ]]; then
        /opt/smartdc/agents/bin/setup-npm-user joyent joyent atropos@joyent.com
    fi
}

function backup_npm_registry
{
    echo "==> Would backup npm registry from atropos"
}

function restore_npm_registry
{
    echo "==> Would restore npm registry to atropos"
}

function upgrade_zones
{
    # Upgrade zones that use app-release-builder
    #
    # EXCEPT pubapi which may have been customized, so is handled separately.
    #
    if [[ -d ${ROOT}/zones ]]; then
        cd ${ROOT}/zones
        for file in `ls *.tbz2 | grep -v ^pubapi-`; do
            gtar -jxf ${file}
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
            echo "INFO: ${usbcpy}/os/${platformversion} already exists, skipping update."
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


mount_usbkey
check_versions
backup_usbkey
upgrade_usbkey
trap cleanup EXIT

# import new headnode dataset if there's one (used for new headnode zones)
import_datasets

backup_npm_registry
recreate_zones
restore_npm_registry
upgrade_zones
reenable_agents

# TODO
#
# If there are agents in ${ROOT}/agents, publish to npm (and apply?)
# If not (default) MAPI will have updated for us
#

install_platform

# TODO: make list of added/removed config options from config.default over config

# Update version, since the upgrade made it here.
echo "${new_version}" > ${usbmnt}/version

exit 0
