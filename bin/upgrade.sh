#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#
# SUMMARY
#
# This is an example upgrade.sh script which shows how one will be built for an
# actual SDC upgrade.
#

PATH=/usr/bin:/usr/sbin:/smartdc/bin
export PATH

BASH_XTRACEFD=4
set -o xtrace

ROOT=$(pwd)
export SDC_UPGRADE_ROOT=${ROOT}
export SDC_UPGRADE_SAVE=/zones

# We use the 6.5 rc11 USB key image build date to check the minimum
# upgradeable version.
VERS_6_5=20110922

date 1>&4 2>&1

RECREATE_ZONES=( \
    assets \
    ca \
    dhcpd \
    rabbitmq \
    mapi \
    adminui \
    capi \
    billapi \
    portal \
    cloudapi \
    riak
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
    [[ -z ${existing_version} ]] && \
        fatal "unable to find version file in ${usbmnt}"

    # Check version to ensure it's possible to apply this update.
    # We only support upgrading from 6.5 or later builds.  The 6.5 rc11
    # build date is in the version string and hardcoded in this script.
    v_old=`echo $existing_version | \
        nawk -F. '{split($1, f, "T"); print f[1]}'`
    [ $v_old -lt $VERS_6_5 ] && \
        fatal "the system must be running at least SDC 6.5 to be upgraded"

    printf "Upgrading from ${existing_version}\n    to ${new_version}\n"
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

        # Add a capi_external_url entry if not there and CAPI has an external
        # IP configured.
	grep "^capi_external_url=" /mnt/usbkey/config >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            # try to add new config entry if CAPI has an external IP
	    capi_external_ip=`grep "^capi_external_ip=" /mnt/usbkey/config`
            if [[ $? == 0 ]]; then
                capi_external_ip=`echo $capi_external_ip | cut -d= -f2`
                echo "capi_external_url=http://$capi_external_ip:8080" \
                    >> /mnt/usbkey/config
            fi
        fi

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

    #
    # When this headnode was first setup, it may have had an incorrect dump
    # device size.  Let's fix that.  The dump device should be half the size of
    # available physical memory.
    #
    local system_pool=$(svcprop -p config/zpool smartdc/init)
    local dumpsize=$(zfs get -Hp -o value volsize ${system_pool}/dump)
    if [[ $dumpsize -eq 4294967296 ]]; then
        local newsize_in_MiB=$(( ${SYSINFO_MiB_of_Memory} / 2 ))
        zfs set volsize=${newsize_in_MiB}m ${system_pool}/dump
    fi
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

function get_sdc_datasets
{
    MAPI_DS=`curl -i -s -u admin:$CONFIG_mapi_http_admin_pw \
        http://${CONFIG_mapi_admin_ip}/datasets?include_disabled=true | \
	json | nawk '{
            if ($1 == "\"name\":") {
                # strip quotes and comma
                nm = substr($2, 2, length($2) - 3)
            }
            if ($1 == "\"version\":") {
                # strip quotes and comma
                v = substr($2, 2, length($2) - 3)
                printf("%s-%s.dsmanifest\n", nm, v)
            }
        }'`
}

function import_sdc_datasets
{
	echo "Import new SDC datasets"

        get_sdc_datasets

	for i in /usbkey/datasets/*.dsmanifest
	do
		bname=${i##*/}

		match=0
		for j in $MAPI_DS
		do
			if [ $bname == $j ]; then
				match=1
				break
			fi
		done

		if [ $match == 0 ]; then
			bzname=`nawk '{
			        if ($1 == "\"path\":") {
			            # strip quotes and colon
			            print substr($2, 2, length($2) - 3)
			            exit 0
			        }
			    }' $i`
			cp $i /tmp
			# We have to mv since dsimport wants to copy it back
			mv /usbkey/datasets/$bzname /tmp

			sed -i "" -e \
"s|\"url\": \"https:.*/|\"url\": \"http://$CONFIG_assets_admin_ip/datasets/|" \
			    /tmp/$bname
			sdc-dsimport /tmp/$bname

			rm -f /tmp/$bname /tmp/$bzname
		fi
	done
}

function upgrade_agents
{
	echo "Upgrade headnode agents"

	# Get the latest agents shar
	AGENTS=`ls -t /usbkey/ur-scripts | head -1`
	echo "Installing agents $AGENTS"
        # There is a bug in the agent installer and we have to run it twice
        # since it fails on the first run.
	bash /usbkey/ur-scripts/$AGENTS 1>&4 2>&1
	bash /usbkey/ur-scripts/$AGENTS 1>&4 2>&1
}

function upgrade_cn_agents
{
	echo "Upgrade compute node agents"

	local assetdir=/zones/assets/root/assets/extra/agents

	mkdir -p $assetdir
	cp /usbkey/ur-scripts/$AGENTS $assetdir

        # There is a bug in the agent installer and we have to run it twice
        # since it fails on the first run.
	sdc-oneachnode -c "cd /var/tmp;
	  curl -kOs $CONFIG_assets_admin_ip:/extra/agents/$AGENTS;
	  (bash /var/tmp/$AGENTS </dev/null >/var/tmp/agent_install.log 2>&1;
	   bash /var/tmp/$AGENTS </dev/null >>/var/tmp/agent_install.log 2>&1)&"

	rm -f $assetdir/$AGENTS
}

function recreate_zones
{
    echo "Re-create zones"

    # dhcpd zone expects this to exist, so make sure it does:
    mkdir -p ${usbcpy}/os

    local zone

    # Upgrade zones we can just recreate
    for zone in "${RECREATE_ZONES[@]}"; do
        if [[ "${zone}" == "capi" && -n ${CONFIG_capi_is_local} \
            && ${CONFIG_capi_is_local} == "false" ]]; then
            echo "--> Skipping CAPI zone, because CAPI is not local."
            continue
        fi

        echo "Re-creating $zone zone"

        mkdir -p ${backup_dir}/zones/${zone}
	# Use the latest backup code from the new upgrade image if possible
        if [[ -x ${usbcpy}/zones/${zone}/backup ]]; then
            ${usbcpy}/zones/${zone}/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        elif [[ -x /zones/${zone}/root/opt/smartdc/bin/backup ]]; then
            /zones/${zone}/root/opt/smartdc/bin/backup ${zone} \
                ${backup_dir}/zones/${zone}/
        else
            echo "Info: stateless, no backup script"
        fi

        # If the zone has a data dataset, copy to the path create-zone.sh
        # expects it for reuse:
        if [[ -f ${backup_dir}/zones/${zone}/${zone}/${zone}-data.zfs ]]; then
          cp ${backup_dir}/zones/${zone}/${zone}/${zone}-data.zfs \
              ${usbcpy}/backup/
        fi

        ${usbcpy}/scripts/destroy-zone.sh ${zone}
        ${usbcpy}/scripts/create-zone.sh ${zone} -w

	# If we've copied the data dataset, remove it.  Also, we know that
	# create-zone will have restored the zone using the copied zfs send
	# stream.  Otherwise, if this zone has some other form of backup,
	# restore the zone now.
        if [[ -f ${usbcpy}/backup/${zone}-data.zfs ]]; then
            rm ${usbcpy}/backup/${zone}-data.zfs
	elif [[ -x ${usbcpy}/zones/${zone}/restore ]]; then
	    zoneadm -z ${zone} halt
	    # wait until zone is halted
            echo "Wait for zone to shutdown"
            while true; do
                sleep 3
                state=`zoneadm -z ${zone} list -p | cut -d: -f3`
                [ "$state" == "installed" ] && break
            done

            ${usbcpy}/zones/${zone}/restore ${zone} ${backup_dir}/zones/${zone}/

	    zoneadm -z ${zone} boot
	fi
    done
}


function install_platform
{
    echo "Install new platform"

    local platformupdate=$(ls ${ROOT}/platform/platform-*.tgz | tail -1)
    if [[ -n ${platformupdate} && -f ${platformupdate} ]]; then
        # 'platformversion' is intentionally global.
        platformversion=$(basename "${platformupdate}" | \
            sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")
    fi

    [ -z "${platformversion}" ] && \
        fatal "unable to determine platform version"

    if [[ -d ${usbcpy}/os/${platformversion} ]]; then
        echo "${usbcpy}/os/${platformversion} already exists, skipping update."
        SKIP_SWITCH=1
        return
    fi

    # cleanup old images from the USB key
    local cnt=$(ls -d ${usbmnt}/os/* | wc -l)
    if [ $cnt -gt 1 ]; then
        # delete all but the last image (current will become previous)
        local del_cnt=$(($cnt - 1))
        for i in $(ls -d ${usbmnt}/os/* | head -$del_cnt)
        do
            rm -rf $i
        done
    fi

    ${usbcpy}/scripts/install-platform.sh file://${platformupdate}

    local plat_id=`curl -s -u admin:$CONFIG_mapi_http_admin_pw \
        http://$CONFIG_mapi_admin_ip/platform_images | json | \
        nawk -v n="$platformversion" '{
        if ($1 == "\"id\":") {
            # strip comma
            id = substr($2, 1, length($2) - 1)
        }
        if ($1 == "\"name\":") {
            # strip quotes and comma
            nm = substr($2, 2, length($2) - 3)
            if (nm == n) {
                   print id
                   exit 0
            }
        }
    }'`

    [ -z "${plat_id}" ] && fatal "unable to determine platform ID"

    echo "Make new platform the default for compute nodes"

    curl -s -u admin:$CONFIG_mapi_http_admin_pw \
        http://$CONFIG_mapi_admin_ip/platform_images/$plat_id/make_default \
        -d '' -X PUT 1>&4 2>&1

    # Get headnode server_role (probably also 1, but get it just in case).
    local srole_id=`curl -s -u admin:$CONFIG_mapi_http_admin_pw \
        http://$CONFIG_mapi_admin_ip/servers/1 | json | nawk '{
            if ($1 == "\"server_role_id\":") {
			# strip comma
			print substr($2, 1, length($2) - 1)
		}
            }'`

    if [ -z "$srole_id" ]; then
        echo "WARNING: unable to find headnode server role" >/dev/stderr
        return
    fi

    curl -s -u admin:$CONFIG_mapi_http_admin_pw \
        http://$CONFIG_mapi_admin_ip/server_roles/$srole_id \
        -d platform_image_id=$plat_id -X PUT 1>&4 2>&1
}

mount_usbkey
check_versions
umount ${usbmnt}
mounted_usb="false"

# Run full backup with the old sdc-backup code, then unpack the backup archive.
# Unfortunately the 6.5 sdc-backup exits 1 even when it succeeds so check for
# existence of backup file.
echo "Creating a backup"
sdc-backup
bfile=`ls /zones/backup-* 2>/dev/null`
[ -z "$bfile" ] && fatal "unable to make a backup"

mount_usbkey

backup_usbkey
upgrade_usbkey
trap cleanup EXIT

upgrade_pools

# import new headnode dataset if there's one (used for new headnode zones)
import_datasets

#
# NOTE: we don't update the config file in any way since we assume this is
# a minor upgrade from one 6.5.x version to another 6.5.y version and thus,
# there are no config file changes necessary.
#

recreate_zones

SKIP_SWITCH=0
install_platform

import_sdc_datasets

upgrade_agents

upgrade_cn_agents

# Update version, since the upgrade made it here.
echo "${new_version}" > ${usbmnt}/version

[ $SKIP_SWITCH == 0 ] && \
    /usbkey/scripts/switch-platform.sh ${platformversion}
echo "Activating upgrade complete"

message="
The new image has been activated. You must reboot the headnode for the upgrade
to fully take effect.  Once you have verified the upgrade is ok, you can remove
the backup in /zones and create a new backup for the latest image.\n\n"
printf "$message"

date 1>&4 2>&1

cp /tmp/perform_upgrade* /var/tmp

exit 0
