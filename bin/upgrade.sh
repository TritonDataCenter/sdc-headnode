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
# IMPORTANT, this purposefully does not include 'portal' and 'pubapi' since those
# zones are handled differently for upgrades (since they may be customized).
#
RECREATE_ZONES=( \
    assets \
    atropos \
    ca \
    dhcpd \
    rabbitmq \
    mapi \
    adminui \
    capi
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

    # Make sure we set the npm user correctly for the atropos registry, since the
    # atropos zone may have been recreated.
    if [[ -x /opt/smartdc/agents/bin/setup-npm-user ]]; then
        /opt/smartdc/agents/bin/setup-npm-user joyent joyent atropos@joyent.com
    fi
}

function backup_npm_registry
{
    atropos_ip=$1
    backup_dir=$2

    mkdir -p ${backup_dir}
    echo "==> Backuping up npm registry from atropos"

    for agent in $(curl -s http://${atropos_ip}:5984/jsregistry/_design/app/_rewrite \
        | json | grep '^  \"' | cut -d '"' -f2); do

        echo "==> Looking for tarballs for agent '${agent}'"
        output=$(curl -s http://${atropos_ip}:5984/jsregistry/${agent}/)
        json_output=$(echo ${output} | /usr/bin/json > "${backup_dir}/${agent}.json")
        declare -a uris

        # Grab the URIs and replace any target with the correct IP (no DNS!)
        # Also fix the URL for npm which for some reason picks a different format.
        uris=$(cat "${backup_dir}/${agent}.json" \
            | grep tarball \
            | awk '{print $2}' \
            | tr -s '"' ' ' \
            | sed -e "s|http://.*:5984|http://${atropos_ip}:5984|" \
            | sed -e "s|:5984/npm/-|:5984/jsregistry/_design/app/_rewrite/npm/-|")

        if [[ -z ${uris} ]]; then
            echo "--> Cannot find agent '${agent}' in atropos registry, skipping"
        else
            for uri in ${uris}; do
                echo "==> Downloading: ${uri}"
                basename=$(echo "${uri}" | sed 's|^.*://.*/||g')
                curl --progress-bar $uri -o "${backup_dir}/${basename}" \
                    || echo "failed to download '${basename}'"
            done
        fi
        rm "${backup_dir}/${agent}.json"
    done
}

function restore_npm_registry
{
    backup_dir=$1

    echo "==> Restoring npm registry to atropos from ${backup_dir}"

    # Once everything is done, go publish them again
    agent_files=$(ls ${backup_dir}/*)
    for agent_file in ${agent_files[@]}; do
        /opt/smartdc/agents/bin/agents-npm publish ${agent_file}
    done
}

function install_new_agents
{
    if [[ -d ${ROOT}/agents ]]; then
        echo "==> Publishing new npm agents to atropos"
        agent_files=$(ls ${ROOT}/agents/*)
        for agent_file in ${agent_files[@]}; do
            /opt/smartdc/agents/bin/agents-npm publish ${agent_file}
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

# import new headnode dataset if there's one (used for new headnode zones)
import_datasets

backup_npm_registry "${CONFIG_atropos_admin_ip}" ${backup_dir}/npm_registry
recreate_zones
restore_npm_registry ${backup_dir}/npm_registry
reenable_agents

# If there are new agents in this upgrade, publish them to atropos
install_new_agents

# new platform!
install_platform

# Update version, since the upgrade made it here.
echo "${new_version}" > ${usbmnt}/version

if [[ $doupgrade == true ]]; then
  /usbkey/scripts/switch-platform.sh ${platformversion}
  index=0
  numservers=$(/smartdc/bin/sdc-mapi /servers | /usr/bin/json -H length )
  while [[ ${index} -lt ${numservers} ]]; do
    echo "Upgrading agents on server ${index} of ${numservers}"
    name=$(basename `/smartdc/bin/sdc-mapi /servers | /usr/bin/json -H ${index}.uri`)
    /smartdc/bin/sdc-mapi /admin/servers/${name}/atropos/install -F "package=agent"
    index=$((${index}+1))
  done
  echo "Activating upgrade complete"
fi
exit 0
