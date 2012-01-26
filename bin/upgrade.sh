#!/bin/bash
#
# Copyright (c) 2011, 2012, Joyent Inc., All rights reserved.
#
# SUMMARY
#
# This upgrade script is delivered inside the upgrade image, so this script
# is from the latest build, but the system will be running an earlier release.
# The perform-upgrade.sh script from the earlier release unpacks the upgrade
# image (which contains this script) into a temporary directory, then runs
# this script.  Thus, the system will be running the old release while this
# script executes and we cannot depend on any new system behavior from the
# current release we're upgrading to.
#

unset LD_LIBRARY_PATH
# /image/usr/sbin is here so we pickup vmadm on 6.5
PATH=/usr/bin:/usr/sbin:/smartdc/bin:/image/usr/sbin
export PATH

BASH_XTRACEFD=4
set -o xtrace

ROOT=$(pwd)
export SDC_UPGRADE_DIR=${ROOT}
export SDC_UPGRADE_SAVE=/var/tmp/upgrade_save

# We use the 6.5 rc11 USB key image build date to check the minimum
# upgradeable version.
VERS_6_5=20110922

# This is the list of zones that did not exist in 6.5 and which have
# no 6.5 equivalent (e.g. ufds replaces capi, so its not in this list).
BRAND_NEW_ZONES="redis amon"

mounted_usb="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' \
    svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' \
    svc:/system/filesystem/smartdc:default)"

. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

. ./upgrade_common

# Ensure we're a SmartOS headnode
if [[ ${SYSINFO_Bootparam_headnode} != "true" \
    || $(uname -s) != "SunOS" \
    || -z ${SYSINFO_Live_Image} ]]; then

    fatal "this can only be run on a SmartOS headnode."
fi

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
        ${usbcpy}/scripts/mount-usb.sh
        mounted_usb="true"
    fi
}

function umount_usbkey
{
	umount /mnt/usbkey
        mounted_usb="false"
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
        fatal "unable to create backup dir ${backup_dir}"
    fi
    mkdir -p ${backup_dir}/usbkey
    mkdir -p ${backup_dir}/zones

    printf "Creating USB backup in\n${backup_dir}\n"

    # touch these, just to make sure they exist (in case of older build)
    touch ${usbmnt}/datasets/smartos.uuid
    touch ${usbmnt}/datasets/smartos.filename
    mkdir -p ${usbmnt}/default

    (cd ${usbmnt} && gtar -cf - \
        boot/grub/menu.lst.tmpl \
        data \
        datasets/smartos.{uuid,filename} \
        default \
        rc \
        scripts \
        ur-scripts \
        zones \
    ) \
    | (cd ${backup_dir}/usbkey && gtar --no-same-owner -xf -)
}

function upgrade_usbkey
{
    local usbupdate=$(ls ${ROOT}/usbkey/*.tgz | tail -1)
    if [[ -n ${usbupdate} ]]; then
        (cd ${usbmnt} && gzcat ${usbupdate} | gtar --no-same-owner -xf -)

        (cd ${usbmnt} && rsync -a --exclude private --exclude os * ${usbcpy})
    fi
}

function import_datasets
{
    local ds_uuid=$(cat ${usbmnt}/datasets/smartos.uuid)
    local ds_file=$(cat ${usbmnt}/datasets/smartos.filename)

    if [[ -z ${ds_uuid} ]]; then
        fatal "no uuid set in ${usbmnt}/datasets/smartos.uuid"
    else
        echo "Ensuring dataset ${ds_uuid} is imported."
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

# Similar to function in /smartdc/lib/sdc-common but we might not have that
# available before we upgrade.  This function will be available on CNs since
# we have sdc-setup there already if we are upgrading them.
check_mapi_err()
{
	hd=$(dd if=/tmp/sdc$$.out bs=1 count=6 2>/dev/null)
	if [ "$hd" == "<html>" ]; then
		emsg="mapi failure"
		return
	fi

	emsg=`json </tmp/sdc$$.out | nawk '{
		if ($1 == "\"errors\":") {
			error=1
			next
		}
		if (error) {
			s=index($0, "\"")
			tmp=substr($0, s + 1)
			print substr(tmp, 1, length(tmp) - 1)
			exit 0
		}
	}'`
	return 0
}

# must do this before we halt mapi
function delete_new_sdc_zones
{
	# post 6.5 zones need to be deleted using sdc-setup -D
	# If we have zones listed in NEW_CLEANUP, then we know they were
	# provisioned through sdc-setup so this system will support deleting
	# them through sdc-setup.
	for zone in $NEW_CLEANUP
	do
		[ "$zone" == "$MAPI_ZONE" ] && continue
		echo "Deleting zone: $zone"
		sdc-setup -D $zone 1>&4 2>&1
	done
}

function delete_old_sdc_zones
{
	# 6.5 zones were not provisioned through mapi
	for zone in $OLD_CLEANUP
	do
		echo "Deleting zone: $zone"
		zoneadm -z $zone halt
		sleep 3
		zoneadm -z $zone uninstall -F
		zonecfg -z $zone delete -F
	done
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
	get_sdc_datasets

	mount_usbkey

	# Look on the key to avoid seeing extra, customer-installed datasets.
	for i in /mnt/usbkey/datasets/*.dsmanifest
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
			echo "Import new dataset $bname"
	
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

	umount_usbkey
}

# Fix up the USB key config file
function cleanup_config
{
	echo "Cleaning up configuration"
	mount_usbkey

	# Only delete these pre-existing entries if upgrading from 6.x,
	# sdc-setup -D removes entries otherwise.
	if [ -n "$OLD_CLEANUP" ]; then
		cat <<-SED_DONE >/tmp/upg.$$
		/^adminui_admin_ip=/d
		/^adminui_external_ip=/d
		/^ca_admin_ip=/d
		/^ca_client_url=/d
		/^portal_external_ip=/d
		/^portal_external_url=/d
		/^cloudapi_admin_ip=/d
		/^cloudapi_external_ip=/d
		/^cloudapi_external_url=/d
		/^riak_admin_ip=/d
		/^billapi_admin_ip=/d
		/^billapi_external_ip=/d
		/^billapi_external_url=/d
		SED_DONE
	fi

	if [ "$CONFIG_capi_is_local" == "true" -o \
	     "$CONFIG_ufds_is_local" == "true" ]; then
		echo "/^capi_/d" >>/tmp/upg.$$
	fi

	sed -f /tmp/upg.$$ </mnt/usbkey/config >/tmp/config.$$

	# If upgrading from a system without ufds, add ufds entries
	egrep -s ufds_ /mnt/usbkey/config
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		ufds_is_local=$CONFIG_capi_is_local
		ufds_external_vlan=0
		ufds_root_pw=$CONFIG_capi_root_pw
		ufds_ldap_root_dn=cn=root
		ufds_ldap_root_pw=secret
		ufds_admin_login=$CONFIG_capi_admin_login
		ufds_admin_pw=$CONFIG_capi_admin_pw
		ufds_admin_email=$CONFIG_capi_admin_email
		ufds_admin_uuid=$CONFIG_capi_admin_uuid
		# Legacy CAPI parameters
		capi_http_admin_user=$CONFIG_capi_http_admin_user
		capi_http_admin_pw=$CONFIG_capi_http_admin_pw
		DONE
	fi

	# If upgrading from a system without redis, add redis entries
	egrep -s redis_ /mnt/usbkey/config
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		redis_root_pw=$CONFIG_adminui_root_pw
		redis_admin_pw=$CONFIG_adminui_admin_pw
		DONE
	fi

	# If upgrading from a system without amon, add amon entries
	egrep -s amon_ /mnt/usbkey/config
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		amon_root_pw=$CONFIG_adminui_root_pw
		amon_admin_pw=$CONFIG_adminui_admin_pw
		DONE
	fi

	cp /tmp/config.$$ /mnt/usbkey/config
	cp /mnt/usbkey/config /usbkey/config
	rm -f /tmp/config.$$ /tmp/upg.$$

	# Load the new pkg values from the upgrade conf.generic into variables.
	eval $(cat ${ROOT}/conf.generic | sed -e "s/^ *//" | grep -v "^#" | \
	    grep "^[a-zA-Z]" | sed -e "s/^/GENERIC_/")

	# If upgrading from a system without sdc pkgs, convert generic config
	egrep -s "^pkg_" /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		# Remove obsolete entries
		cat <<-SED_DONE >/tmp/upg.$$
			/^adminui_cpu_shares/d
			/^adminui_max_lwps/d
			/^adminui_memory_cap/d
			/^billapi_/d
			/^ca_/d
			/^capi_/d
			/^cloudapi_/d
			/^portal_/d
			/^riak_/d
		SED_DONE

		sed -f /tmp/upg.$$ </mnt/usbkey/config.inc/generic \
		    >/tmp/config.$$

		pkgs=`set | nawk -F=  '/^GENERIC_pkg_/ {print $2}'`

		# add all pkg_ entries from upgrade generic file
		echo "" >>/tmp/config.$$
		cnt=1
		for i in $pkgs
		do
			echo "pkg_$cnt=$i" >>/tmp/config.$$
			cnt=$((cnt + 1))
		done

		# add new zone entries
		cat <<-DONE >>/tmp/config.$$

		adminui_pkg=${GENERIC_adminui_pkg}
		assets_pkg=${GENERIC_assets_pkg}
		billapi_pkg=${GENERIC_billapi_pkg}
		ca_pkg=${GENERIC_ca_pkg}
		cloudapi_pkg=${GENERIC_cloudapi_pkg}
		dhcpd_pkg=${GENERIC_dhcpd_pkg}
		mapi_pkg=${GENERIC_mapi_pkg}
		portal_pkg=${GENERIC_portal_pkg}
		rabbitmq_pkg=${GENERIC_rabbitmq_pkg}
		riak_pkg=${GENERIC_riak_pkg}
		DONE
	else
		cp /mnt/usbkey/config.inc/generic /tmp/config.$$
	fi

	# Add any missing entries for new roles that didn't used to exist.

	egrep -s ufds_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		echo "ufds_pkg=${GENERIC_ufds_pkg}" >>/tmp/config.$$
	fi

	egrep -s redis_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		echo "redis_pkg=${GENERIC_redis_pkg}" >>/tmp/config.$$
	fi

	egrep -s amon_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		echo "amon_pkg=${GENERIC_amon_pkg}" >>/tmp/config.$$
	fi

	cp /tmp/config.$$ /mnt/usbkey/config.inc/generic
	cp /mnt/usbkey/config.inc/generic /usbkey/config.inc/generic
	rm -f /tmp/config.$$ /tmp/upg.$$

	umount_usbkey
}

# Update the CN config file that mapi uses.
function cleanup_cn_config
{
	# Depends on the mapi zonename we found in recreate_core_zones
	local conf=/zones/$MAPIZONE/root/opt/smartdc/node.config/node.config
	local nconf=/tmp/config.new.$$

	echo "Updating compute node configuration"
	nawk -F= '{
	    if ($1 == "capi_admin_ip")
	        printf("ufds_admin_ip=%s\n", $2)
	    else if ($1 == "capi_admin_uuid")
	        printf("ufds_admin_uuid=%s\n", $2)
	    else
	        print $0
	}' $conf > $nconf

	egrep -s "^mapi_client_url" $conf || \
	    echo "mapi_client_url='$CONFIG_mapi_client_url'" >> $nconf
	egrep -s "^mapi_http_admin_user" $conf || \
	    echo "mapi_http_admin_user='$CONFIG_mapi_http_admin_user'" >> $nconf
	egrep -s "^mapi_http_admin_pw" $conf || \
	    echo "mapi_http_admin_pw='$CONFIG_mapi_http_admin_pw'" >> $nconf

	mv $nconf $conf
}

# We restore the core zones as a side-effect during creation.
function recreate_core_zones
{
	echo "Re-creating core zones"
	# dhcpd zone expects this to exist, so make sure it does:
	mkdir -p ${usbcpy}/os

	export SKIP_AGENTS=1
	export SKIP_SDC_PKGS=1
	/usbkey/scripts/headnode.sh 1>&4 2>&1

	# Wait for mapi to be ready before we move on
	cnt=0
	while [ $cnt -lt 11 ]
	do
		curl -f -s \
		-u ${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw} \
		    http://$CONFIG_mapi_admin_ip/servers >/dev/null 2>&1
		[ $? == 0 ] && break
		let cnt=$cnt+1
		sleep 30
	done
	[ $cnt -eq 11 ] && \
	    echo "Warning: MAPI still not ready after 5 minutes"

	# headnode.sh left the zones running, shut down so we can restore them
	for zone in `zoneadm list`
	do
		[ "$zone" == "global" ] && continue
		zoneadm -z $zone halt
	done

	local admin_uuid=${CONFIG_ufds_admin_uuid}

	# Restore core zones
	for zone in \
	$(vmadm lookup owner_uuid=${admin_uuid} tags.smartdc_role=~^[a-z])
	do
		local role=$(vmadm get $zone | json -a tags.smartdc_role)

		# Save the mapi zonename for later
		[ "$role" == "mapi" ] && MAPIZONE=$zone

		# If this zone has some form of backup, restore the zone now.
		if [[ -x ${usbcpy}/zones/${role}/restore ]]; then
			echo "Restore $role zone"
			${usbcpy}/zones/${role}/restore ${zone} \
			    ${SDC_UPGRADE_DIR}/bu.tmp 1>&4 2>&1
		fi
	done

	# Boot core zones
	for zone in \
	$(vmadm lookup owner_uuid=${admin_uuid} tags.smartdc_role=~^[a-z])
	do
		zoneadm -z $zone boot
	done
}

# Upgrade internal-use packages
function upgrade_sdc_pkgs
{
    local pkgs=`set | nawk -F= '/^CONFIG_pkg/ {print $2}'`
    for p in $pkgs
    do
        # Pkg entry format:
        # name:ram:swap:disk:cap:nlwp:iopri
        local nm=${p%%:*}
        p=${p#*:}
        local ram=${p%%:*}
        p=${p#*:}
        local swap=${p%%:*}
        p=${p#*:}
        local disk=${p%%:*}
        p=${p#*:}
        local cap=${p%%:*}
        p=${p#*:}
        local nlwp=${p%%:*}
        p=${p#*:}
        local iopri=${p%%:*}

        curl -i -s \
            -u ${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw} \
            http://$CONFIG_mapi_admin_ip/packages \
            -X POST \
            -d name=$nm \
            -d ram=$ram \
            -d swap=$swap \
            -d disk=$disk \
            -d cpu_cap=$cap \
            -d lightweight_processes=$nlwp \
            -d zfs_io_priority=$iopri \
            -d owner_uuid=$CONFIG_ufds_admin_uuid 1>&4 2>&1
    done
}

# Transform CAPI pg_dumps into LDIF, then load into UFDS
# capi dump files are in $SDC_UPGRADE_SAVE/capi_dump
function convert_capi_ufds
{
	echo "Transforming CAPI postgres dumps to LDIF."
	${usbcpy}/scripts/capi2ldif.sh ${SDC_UPGRADE_SAVE}/capi_dump \
	    > $SDC_UPGRADE_SAVE/capi_dump/ufds.ldif

	# We're on the headnode, so we know the zonepath is in /zones.
	cp $SDC_UPGRADE_SAVE/capi_dump/ufds.ldif /zones/$1/root

	# Wait up to 2 minutes for ufds zone to be ready
	echo "Waiting for ufds zone to finish booting"
	local cnt=0
	while [ $cnt -lt 12 ]; do
		sleep 10
		local scnt=`svcs -z $1 -x 2>/dev/null | wc -l`
		[ $scnt == 0 ] && break
		cnt=$(($cnt + 1))
	done
	[ $cnt == 12 ] && \
	    echo "WARNING: some ufds svcs still not ready after 2 minutes"

	# re-load config to pick up settings for newly created ufds zone
	load_sdc_config

	echo "Running ldapadd on transformed CAPI data"
	zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
	    -H ${CONFIG_ufds_client_url} \
	    -D ${CONFIG_ufds_ldap_root_dn} \
	    -w ${CONFIG_ufds_ldap_root_pw} \
	    -f /ufds.ldif 1>&4 2>&1

	rm -f /zones/$1/root/ufds.ldif
}

function install_platform
{
	local platformupdate=$(ls ${ROOT}/platform/platform-*.tgz | tail -1)
	if [[ -n ${platformupdate} && -f ${platformupdate} ]]; then
		# 'platformversion' is intentionally global.
		platformversion=$(basename "${platformupdate}" | \
		    sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")
	fi

	[ -z "${platformversion}" ] && \
	    fatal "unable to determine platform version"

	if [[ -d ${usbcpy}/os/${platformversion} ]]; then
		echo \
	    "${usbcpy}/os/${platformversion} already exists, skipping update."
		SKIP_SWITCH=1
		return
        fi

	mount_usbkey

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

	echo "Unpacking ${platformversion} to ${usbmnt}/os"
	curl --progress -k file://${platformupdate} | \
	    (mkdir -p ${usbmnt}/os/${platformversion} \
	    && cd ${usbmnt}/os/${platformversion} \
	    && gunzip | tar -xf - 2>/tmp/install_platform.log \
	    && mv platform-* platform
	    )

	[[ -f ${usbmnt}/os/${platformversion}/platform/root.password ]] && \
	    mv -f ${usbmnt}/os/${platformversion}/platform/root.password \
		${usbmnt}/private/root.password.${platformversion}

	echo "Copying ${platformversion} to ${usbcpy}/os"
	mkdir -p ${usbcpy}/os
	(cd ${usbmnt}/os && \
	    rsync -a ${platformversion}/ ${usbcpy}/os/${platformversion})

	umount_usbkey
}

function register_platform
{
	echo "Register new platform with MAPI"

	local plat_id

	# We can still see intermittent mapi errors after we just started mapi
	# back up, even though we already checked mapi and it seemed to be
	# running. Retry this command a few times if necessary.
	local cnt=0
	while [ $cnt -lt 5 ]; do
		curl -s -u admin:$CONFIG_mapi_http_admin_pw \
		    http://$CONFIG_mapi_admin_ip/platform_images \
		    -d platform_type=smartos -d name=$platformversion -X POST \
		    >/tmp/sdc$$.out 2>&1
		check_mapi_err
		if [ -z "$emsg" ]; then
			plat_id=`json </tmp/sdc$$.out | nawk '{
				if ($1 == "\"id\":") {
					# strip comma
					print substr($2, 1, length($2) - 1)
					exit 0
				}
			    }'`
			rm -f /tmp/sdc$$.out
			[ -n "$plat_id" ] && break
		fi

		echo "Error: MAPI failed to register platform" >/dev/stderr
		printf "       %s\n" "$emsg" >/dev/stderr
		echo "Retrying in 60 seconds" >/dev/stderr

		sleep 60
		cnt=$(($cnt + 1))
	done
	if [ $cnt -ge 5 ]; then
		echo "Error: registering platform failed after 5 retries" \
		    >/dev/stderr
		return
	fi

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
			exit 0
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

function upgrade_agents
{
	# Get the latest agents shar
	local agents=`ls -t /usbkey/ur-scripts | head -1`
	echo "Installing agents $agents"
	bash /usbkey/ur-scripts/$agents 1>&4 2>&1
}

function upgrade_cn_agents
{
	echo "Upgrade compute node agents"

	local agents=`ls -t /usbkey/ur-scripts | head -1`
	local assetdir=/usbkey/extra/agents

	mkdir -p $assetdir
	cp /usbkey/ur-scripts/$agents $assetdir

	sdc-oneachnode -c "cd /var/tmp;
	  curl -kOs $CONFIG_assets_admin_ip:/extra/agents/$agents;
	  (bash /var/tmp/$agents </dev/null >/var/tmp/agent_install.log 2>&1)&"

	rm -f $assetdir/$agents
}

rm -rf $SDC_UPGRADE_SAVE
mkdir -p $SDC_UPGRADE_SAVE

HEADNODE=1

mount_usbkey
check_versions
umount_usbkey

# Make sure we can talk to the old MAPI
curl -s -u admin:$CONFIG_mapi_http_admin_pw \
    http://$CONFIG_mapi_admin_ip/servers >/tmp/sdc$$.out 2>&1
check_mapi_err
rm -f /tmp/sdc$$.out
[ -n "$emsg" ] && fatal "MAPI API is not responding"

get_sdc_zonelist

if [ $CAPI_FOUND == 1 ]; then
	# dump capi
	echo "Dump CAPI for RIAK conversion"
	mkdir -p $SDC_UPGRADE_SAVE/capi_dump
	tables=`zlogin capi /opt/local/bin/psql -h127.0.0.1 -Upostgres -w \
	    -Atc '\\\\dt' capi | cut -d '|' -f2`
	for i in $tables
	do
		zlogin capi /opt/local/bin/pg_dump -Fp -w -a -EUTF-8 \
		    -Upostgres -h127.0.0.1 -t $i capi \
		    >$SDC_UPGRADE_SAVE/capi_dump/$i.dump
	done
fi

trap cleanup EXIT

# There is a fairly complex sequence we have to go through here to shutdown
# most of the zones so we are in a more stable state for backup, then to
# delete the zones.  In addtion, if we're upgrading from 6.x, then we cannot
# shutdown the zones before backing up, since 6.x backup depends on the zones
# running.
#
# We need assets up to be able to backup.
# We need mapi up so that we can delete the zones using sdc-setup -D.
[ $OLD_STYLE_ZONES == 0 ] && shutdown_non_core_zones

# Run full backup with the old sdc-backup code, then unpack the backup archive.
# Unfortunately the 6.5 sdc-backup exits 1 even when it succeeds so check for
# existence of backup file.
echo "Creating a backup"
sdc-backup -s datasets -d $SDC_UPGRADE_SAVE
bfile=`ls $SDC_UPGRADE_SAVE/backup-* 2>/dev/null`
[ -z "$bfile" ] && fatal "unable to make a backup"

# We no longer need the assets zone up now that backup is complete
[ $OLD_STYLE_ZONES == 0 ] && shutdown_zone $ASSETS_ZONE

mkdir $SDC_UPGRADE_DIR/bu.tmp
(cd $SDC_UPGRADE_DIR/bu.tmp; gzcat $bfile | tar xbf 512 -)

mount_usbkey

backup_usbkey
upgrade_usbkey

upgrade_pools

# import new headnode datasets (used for new headnode zones)
import_datasets

umount_usbkey

# We start by deleting all new-style zones except for mapi
echo "Cleaning up existing zones"
delete_new_sdc_zones
# Wait a bit for zone deletion to finish
sleep 10
[ $OLD_STYLE_ZONES == 0 ] && shutdown_zone $MAPI_ZONE
delete_old_sdc_zones
if [ "$MAPI_ZONE" != "mapi" ]; then
	# Now we can delete new-style mapi zone using vmadm
	echo "Deleting zone: $MAPI_ZONE"
	vmadm delete $MAPI_ZONE
fi

cleanup_config
load_sdc_config

# We do the first part of installing the platform now so the new platform
# is available for the new code to run on via the lofs mounts below.
SKIP_SWITCH=0
install_platform

# We need the latest smartdc tools to provision the extra zones.
echo "Mount the new image"
mkdir -p /image
mount -F ufs /usbkey/os/${platformversion}/platform/i86pc/amd64/boot_archive \
    /image
mount -F lofs /image/smartdc /smartdc

# Make sure zones and agents have the latest /usr/node_modules, json and zones
# commands.
# Trying to mount all of usr with the following command will lead to deadlock:
#     mount -F ufs -o ro -O /image/usr.lgz /usr
# We also need a few pieces from the latest /usr/vm, but 6.x doesn't have that
# so we can't just lofs mount.  Intead we setup a writeable node_modules in
# /tmp, make it look like we want, then lofs mount that.
mount -F ufs -o ro /image/usr.lgz /image/usr
mkdir /tmp/node_modules
cp -pr /image/usr/node_modules/* /tmp/node_modules
cp -p /image/usr/vm/node_modules/* /tmp/node_modules
sed -e 's%/usr/vm/sbin/zoneevent%/image/usr/vm/sbin/zoneevent%' \
    /image/usr/vm/node_modules/VM.js >/tmp/node_modules/VM.js
mount -F lofs -o ro /tmp/node_modules /usr/node_modules
mount -F lofs -o ro /image/usr/bin/json /usr/bin/json
mount -F lofs -o ro /image/usr/sbin/zlogin /usr/sbin/zlogin
mount -F lofs -o ro /image/usr/sbin/zoneadm /usr/sbin/zoneadm
mount -F lofs -o ro /image/usr/sbin/zonecfg /usr/sbin/zonecfg

# If we're upgrading an image with vmadm, make sure we use the new one
# by lofs mounting over the old one.
[ -f /usr/sbin/vmadm ] && \
    mount -F lofs -o ro /image/usr/sbin/vmadm /usr/sbin/vmadm

# All of the following are using node and/or libzonecfg so we need to stop them
# before we can lofs mount the new files.
svcadm disable zones-monitoring
svcadm disable smartlogin
svcadm disable cainstsvc
svcadm disable zonetracker-v2
svcadm disable metadata
svcadm disable webinfo
svcadm disable vmadmd
svcadm disable ur
# wait a few seconds for these svcs to stop using libzonecfg
cnt=0
while [ $cnt -lt 3 ]; do
	sleep 5
	mount -F lofs -o ro /image/usr/lib/libzonecfg.so.1 \
	    /usr/lib/libzonecfg.so.1
	[ $? == 0 ] && break
	cnt=$(($cnt + 1))
	fuser -f /usr/lib/libzonecfg.so.1 1>&4 2>&1
	ps -ef 1>&4 2>&1
	svcs -a | grep smartdc 1>&4 2>&1
	svcs -xv 1>&4 2>&1
done
mount -F lofs -o ro /image/usr/bin/node /usr/bin/node
mount -F lofs -o ro /image/usr/lib/zones /usr/lib/zones
svcadm enable ur
svcadm enable vmadmd
svcadm enable metadata
svcadm enable zonetracker-v2
# leave the other svcs disabled until reboot

upgrade_agents

upgrade_cn_agents

# We restore the core zones here as well.
recreate_core_zones

# Wait till core zones are back up before we try to talk to mapi.
echo "Waiting for core zones to be ready"
cnt=0
while [ $cnt -lt 18 ]; do
	bad_svcs=`svcs -Zx 2>/dev/null | wc -l`
	[ $bad_svcs == 0 ] && break
	sleep 10
	cnt=$(($cnt + 1))
done
[ $cnt == 18 ] && echo "WARNING: core svcs still not running after 3 minutes"

# Make sure we can talk to the new MAPI
curl -s -u admin:$CONFIG_mapi_http_admin_pw \
    http://$CONFIG_mapi_admin_ip/servers >/tmp/sdc$$.out 2>&1
check_mapi_err
rm -f /tmp/sdc$$.out
[ -n "$emsg" ] && fatal "MAPI API is not responding, the upgrade is incomplete"

# Now that mapi is restored and back up, load new sdc packages and register
# the new platform with mapi
upgrade_sdc_pkgs
register_platform

import_sdc_datasets

# Update version, since the upgrade made it here.
echo "${new_version}" > ${usbmnt}/version

# We have to re-delete since we restored mapi from a backup.
# The zones should be cleaned up in the file system but we need to cleanup the
# mapi DB.
echo "Cleaning up MAPI database"
delete_new_sdc_zones
# Wait a bit for zone deletion to finish
sleep 10

recreate_extra_zones

# Fix up mapi's CN config file
cleanup_cn_config

[ $SKIP_SWITCH == 0 ] && \
    /usbkey/scripts/switch-platform.sh ${platformversion} 1>&4 2>&1

# Leave headnode setup for compute node upgrades of all roles
for role in $ROLE_ORDER
do
	assetdir=/usbkey/extra/$role
        mkdir -p $assetdir
        cp -pr /usbkey/zones/$role/* $assetdir
        cp -p /usbkey/config $assetdir/hn_config
        cp -p /usbkey/config.inc/generic $assetdir/hn_generic
done
assetdir=/usbkey/extra/upgrade
rm -rf $assetdir
mkdir -p $assetdir
cp upgrade_common $assetdir
cp upgrade_cn $assetdir
cp /zones/$MAPIZONE/root/opt/smartdc/node.config/node.config $assetdir/config

message="
The new image has been activated. You must reboot the system for the upgrade
to take effect.  Once you have verified the upgrade is ok, you can remove the
$SDC_UPGRADE_SAVE directory and its contents.\n\n"
printf "$message"

cp /tmp/perform_upgrade.* $SDC_UPGRADE_SAVE
exit 0
