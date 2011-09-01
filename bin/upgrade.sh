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
# Zones we used to have, but which are no more.
#
OBSOLETE_ZONES=( \
    atropos \
    pubapi
)

#
# IMPORTANT, this purposefully does not include 'portal' since that
# zone is handled differently for upgrades (since it may be customized).
#
RECREATE_ZONES=( \
    assets \
    ca \
    dhcpd \
    rabbitmq \
    mapi \
    adminui \
    capi \
    billapi
)

mounted_usb="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

doupgrade=false
if [[ $1 == "-d" ]]; then
  doupgrade=true
fi

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

function upgrade_usbkey
{
    local usbupdate=$(ls ${ROOT}/usbkey/*.tgz | tail -1)
    if [[ -n ${usbupdate} ]]; then
        (cd ${usbmnt} && gzcat ${usbupdate} | gtar --no-same-owner -xf -)

        # XXX (this is the point where we'd fix the config in /mnt/usbkey/config)
        (cd ${usbmnt} && rsync -a --exclude private --exclude os * ${usbcpy})
    fi
}

function upgrade_pools
{
    #
    # All ZFS pools should have atime=off.  If an operator wants to enable atime
    # on a particular dataset, this setting won't affect that setting, since any
    # datasets with a modified atime property will no longer inherit that
    # setting from the pool's setting.
    #
    local pool
    for pool in $(zpool list -H -o name); do
         zfs set atime=off ${pool} || \
              fatal "failed to set atime=off on pool ${pool}"
    done
}

function import_datasets
{
    local ds_uuid=$(cat ${usbmnt}/datasets/smartos.uuid)
    local ds_file=$(cat ${usbmnt}/datasets/smartos.filename)

    if [[ -z ${ds_uuid} ]]; then
        fatal "no uuid set in ${usbmnt}/datasets/smartos.uuid"
    else
        echo "==> Ensuring ${ds_uuid} is imported."
        if [[ -z $(zfs list | grep "^zones/${ds_uuid}") ]]; then
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
    # dhcpd zone expects this to exist, so make sure it does:
    mkdir -p ${usbcpy}/os

    # Delete obsolete zones
    local zone
    for zone in "${OBSOLETE_ZONES[@]}"; do
        ${usbcpy}/scripts/destroy-zone.sh ${zone}
    done

    # Upgrade zones we can just recreate
    for zone in "${RECREATE_ZONES[@]}"; do
        if [[ "${zone}" == "capi" && -n ${CONFIG_capi_is_local} \
            && ${CONFIG_capi_is_local} == "false" ]]; then
            echo "--> Skipping CAPI zone, because CAPI is not local."
            continue
        fi
        mkdir -p ${backup_dir}/zones/${zone}
        if [[ -x /zones/${zone}/root/opt/smartdc/bin/backup ]]; then
            /zones/${zone}/root/opt/smartdc/bin/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        elif [[ -x ${usbcpy}/zones/${zone}/backup ]]; then
            ${usbcpy}/zones/${zone}/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        else
            echo "--> Warning: No backup script!"
        fi

        # If the zone has a data dataset, copy to the path create-zone.sh
        # expects it for reuse:
        if [[ -f ${backup_dir}/zones/${zone}/${zone}/${zone}-data.zfs ]]; then
          cp ${backup_dir}/zones/${zone}/${zone}/${zone}-data.zfs ${usbcpy}/backup/
        fi

        ${usbcpy}/scripts/destroy-zone.sh ${zone}
        ${usbcpy}/scripts/create-zone.sh ${zone} -w

        # If we've copied the data dataset, remove it:
        if [[ -f ${usbcpy}/backup/${zone}-data.zfs ]]; then
          rm ${usbcpy}/backup/${zone}-data.zfs
        fi
    done
}


function install_platform
{
    # Install new platform
    local platformupdate=$(ls ${ROOT}/platform/platform-*.tgz | tail -1)
    if [[ -n ${platformupdate} && -f ${platformupdate} ]]; then
        # 'platformversion' is intentionally global.
        platformversion=$(basename "${platformupdate}" | sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")

        if [[ -z ${platformversion} || ! -d ${usbcpy}/os/${platformversion} ]]; then
            ${usbcpy}/scripts/install-platform.sh file://${platformupdate}
        else
            echo "INFO: ${usbcpy}/os/${platformversion} already exists, skipping update."
        fi
    fi
}

mount_usbkey

#
# TODO: check a list of required config options and ensure config has them.
# If existing config does not have them, tell the user to go add them and
# go into a sleep loop, waiting for the config options to be there.  User
# can add them from another terminal then we'll continue.  We can also
# print the list with their default values from the new config.default.
#

check_versions
backup_usbkey
upgrade_usbkey
trap cleanup EXIT

upgrade_pools

# import new headnode dataset if there's one (used for new headnode zones)
import_datasets

recreate_zones

# new platform!
install_platform

# Update version, since the upgrade made it here.
echo "${new_version}" > ${usbmnt}/version

if [[ $doupgrade == true ]]; then
  /usbkey/scripts/switch-platform.sh ${platformversion}
  echo "Activating upgrade complete"
fi
exit 0
