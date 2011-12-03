#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
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
PATH=/usr/bin:/usr/sbin:/smartdc/bin
export PATH

BASH_XTRACEFD=4
set -o xtrace

declare -A ZONE_ADMIN_IP=()
declare -A ZONE_EXTERNAL_IP=()

ROOT=$(pwd)
export SDC_UPGRADE_DIR=${ROOT}
export SDC_UPGRADE_SAVE=/var/tmp/upgrade_save

# We use the 6.5 rc11 USB key image build date to check the minimum
# upgradeable version.
VERS_6_5=20110922

CORE_ZONES="assets dhcpd mapi rabbitmq"
OLD_EXTRA_ZONES="adminui billapi ca capi cloudapi portal riak"

# This is the dependency order that extra zones must be installed in.
ROLE_ORDER="ca riak ufds redis amon adminui billapi cloudapi portal"

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

# Ensure we're a SmartOS headnode
if [[ ${SYSINFO_Bootparam_headnode} != "true" \
    || $(uname -s) != "SunOS" \
    || -z ${SYSINFO_Live_Image} ]]; then

    fatal "this can only be run on a SmartOS headnode."
fi

function fatal
{
    msg=$1

    echo "ERROR: ${msg}" >/dev/stderr
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
# available before we upgrade.
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

# Get the mapi network uri for the given tag (admin or external)
function get_net_tag_uri
{
	NET_URI=`curl -s -u admin:$CONFIG_mapi_http_admin_pw \
	    http://$CONFIG_mapi_admin_ip/networks | json | nawk -v tag=$1 '{
		if ($1 == "\"name\":") {
			# strip quotes and comma
			if (substr($2, 2, length($2) - 3) == tag)
				found = 1
		}
		if (found && $1 == "\"uri\":") {
			# strip quotes and comma
			print substr($2, 2, length($2) - 3)
			exit 0
		}
	    }'`
}

# We need to unreserve the IP addrs for the extra zones since those are
# intermixed with the core zones.  We leave the two ranges:
#     dhcp_range_start - dhcp_range_end
#     external_provisionable_start - external_provisionable_end
# as-is in the config file but now the extra zones can keep their previously
# statically allocated IP addresses even though they are outside these ranges.
# It doesn't hurt to unreserve addrs that are not reserved, so for simplicity
# we always just do this.  We unreserve the addrs as we go along recreating
# the extra zones to ensure that new zones without previously allocated addrs
# won't steal one of the addrs needed by an old extra zone.
function unreserve_ip_addrs
{
	get_net_tag_uri "admin"
	ip="${ZONE_ADMIN_IP[$1]}"
	[ -n "$ip" ] && \
	    curl -i -s -u admin:$CONFIG_mapi_http_admin_pw \
	    http://${CONFIG_mapi_admin_ip}${NET_URI}/ips/unreserve \
	    -X PUT -d start_ip=$ip -d end_ip=$ip | json 1>&4 2>&1

	get_net_tag_uri "external"
	ip="${ZONE_EXTERNAL_IP[$1]}"
	[ -n "$ip" ] && \
	    curl -i -s -u admin:$CONFIG_mapi_http_admin_pw \
	    http://${CONFIG_mapi_admin_ip}${NET_URI}/ips/unreserve \
	    -X PUT -d start_ip=$ip -d end_ip=$ip | json 1>&4 2>&1
}

# $1 zone name
# $2 role
# Save the zone's admin and external IP addrs in the associative arrays keyed
# on the zone's role.
function get_zone_addrs
{
	addr=`zonecfg -z $1 info net | nawk -v nic="admin" '{
	    if ($1 == "global-nic:" && $2 == nic)
		found = 1
	    if (found && $1 == "property:") {
		if (index($2, "name=ip,") != 0) {
		    p = index($2, "value=")
		    s = substr($2, p + 7)
		    p = index(s, "\"")
		    s = substr(s, 1, p - 1)
		    print s
		    exit 0
		}
	    }
	}'`
	[ -n "$addr" ] && ZONE_ADMIN_IP[$2]="$addr"

	addr=`zonecfg -z $1 info net | nawk -v nic="external" '{
	    if ($1 == "global-nic:" && $2 == nic)
		found = 1
	    if (found && $1 == "property:") {
		if (index($2, "name=ip,") != 0) {
		    p = index($2, "value=")
		    s = substr($2, p + 7)
		    p = index(s, "\"")
		    s = substr(s, 1, p - 1)
		    print s
		    exit 0
		}
	    }
	}'`
	[ -n "$addr" ] && ZONE_EXTERNAL_IP[$2]="$addr"
}

function get_sdc_zonelist
{
	ZONE_LIST=$CORE_ZONES
	ROLE_LIST=""
	OLD_CLEANUP="$CORE_ZONES"
	NEW_CLEANUP=""

	OLD_STYLE_ZONES=0
	CAPI_FOUND=0
	RIAK_FOUND=0

	# Check for extra zones
	for zone in `zoneadm list -cp | cut -f2 -d:`
	do
		[ "$zone" == "global" ] && continue

		# Check for old-style name-based zone
		match=0
		for i in $OLD_EXTRA_ZONES
		do
			if [ $i == $zone ]; then
				match=1
				# Remember we saw the capi zone so we can
				# convert to ufds later.
				[ $i == "capi" ] && CAPI_FOUND=1

				[ $i == "riak" ] && RIAK_FOUND=1
				break
			fi
		done

		if [ $match == 1 ]; then
			ZONE_LIST="$ZONE_LIST $zone"
			ROLE_LIST="$ROLE_LIST $zone"
			OLD_CLEANUP="$OLD_CLEANUP $zone"
			OLD_STYLE_ZONES=1

			get_zone_addrs $zone $zone
			continue
		fi

		# Check for new-style role-based zone
		zpath=`zoneadm -z $zone list -p | cut -d: -f4`
		sdir=`ls -d $zpath/root/var/smartdc/* 2>/dev/null`
		[ -z "$sdir" ] && continue

		role=${sdir##*/}
		ZONE_LIST="$ZONE_LIST $zone"
		ROLE_LIST="$ROLE_LIST $role"
		NEW_CLEANUP="$NEW_CLEANUP $zone"
		get_zone_addrs $zone $role

		[ $role == "riak" ] && RIAK_FOUND=1
	done
}

function shutdown_non_core_zones
{
	[ -n "$NEW_CLEANUP" ] && echo "Shutting down non-core zones"
	for zone in $NEW_CLEANUP
	do
		zoneadm -z $zone halt
	done
}

function shutdown_remaining_zones
{
	echo "Shutting down running zones"
	for zone in `zoneadm list`
	do
		[ "$zone" == "global" ] && continue
		zoneadm -z $zone halt
	done
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
		sdc-setup -D $zone 1>&4 2>&1
	done
}

function delete_old_sdc_zones
{
	# 6.5 zones were not provisioned through mapi
	for zone in $OLD_CLEANUP
	do
		zoneadm -z $zone uninstall -F
		zonecfg -z $zone delete -F
	done
}

function get_sdc_datasets
{
	MAPI_DS=`curl -i -s -u admin:$CONFIG_mapi_http_admin_pw \
	    http://${CONFIG_mapi_admin_ip}/datasets | json | nawk '{
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
			mv $i /tmp
			bzname=${bname%.*}
			mv /usbkey/datasets/$bzname.zfs.bz2 /tmp

			sed -i "" -e \
"s|\"url\": \"https:.*/|\"url\": \"http://$CONFIG_assets_admin_ip/datasets/|" \
			    /tmp/$bname
			sdc-dsimport /tmp/$bname

			rm -f /tmp/$bname /tmp/$bzname.zfs.bz2
		fi
	done
}

# Fix up the USB key config file
function cleanup_config
{
	echo "Cleaning up configuration"
	mount_usbkey

	cat <<-SED_DONE >/tmp/upg.$$
	/adminui_admin_ip=*/d
	/adminui_external_ip=*/d
	/ca_admin_ip=*/d
	/ca_client_url=*/d
	/portal_external_ip=*/d
	/portal_external_url=*/d
	/cloudapi_admin_ip=*/d
	/cloudapi_external_ip=*/d
	/cloudapi_external_url=*/d
	/riak_admin_ip=*/d
	/billapi_admin_ip=*/d
	/billapi_external_ip=*/d
	/billapi_external_url=*/d
	SED_DONE

	if [ "$CONFIG_capi_is_local" == "true" -o \
	     "$CONFIG_ufds_is_local" == "true" ]; then
		echo "/capi_*/d" >>/tmp/upg.$$
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

	# Now adjust the memory caps in the generic file

	if [ "$CONFIG_coal" == "true" ]; then
		ca_cap="256m"
		riak_cap="256m"
	else
		ca_cap="1024m"
		riak_cap="512m"
	fi

	cat <<-SED_DONE >/tmp/upg.$$
	s/adminui_memory_cap=.*/adminui_memory_cap=128m/
	s/billapi_memory_cap=.*/billapi_memory_cap=128m/
	s/ca_memory_cap=.*/ca_memory_cap=${ca_cap}/
	s/cloudapi_memory_cap=.*/cloudapi_memory_cap=128m/
	s/portal_memory_cap=.*/portal_memory_cap=128m/
	s/riak_memory_cap=.*/riak_memory_cap=${riak_cap}/
	/capi_*/d
	SED_DONE

	sed -f /tmp/upg.$$ </mnt/usbkey/config.inc/generic >/tmp/config.$$

	egrep -s ufds_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		ufds_cpu_shares=100
		ufds_max_lwps=1000
		ufds_memory_cap=256m
		DONE
	fi

	egrep -s redis_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		redis_cpu_shares=50
		redis_max_lwps=1000
		redis_memory_cap=128m
		DONE
	fi

	egrep -s amon_ /mnt/usbkey/config.inc/generic
	if [ $? != 0 ]; then
		cat <<-DONE >>/tmp/config.$$
		amon_cpu_shares=100
		amon_max_lwps=1000
		amon_memory_cap=256m
		DONE
	fi

	cp /tmp/config.$$ /mnt/usbkey/config.inc/generic
	cp /mnt/usbkey/config.inc/generic /usbkey/config.inc/generic
	rm -f /tmp/config.$$ /tmp/upg.$$

	umount_usbkey
}

# We restore the core zones as a side-effect during creation.
# The create-zone script sees the presence of the ${zone}-data.zfs file
# and sets KEEP_DATA_DATASET.
function recreate_core_zones
{
	echo "Recreating core zones"
	# dhcpd zone expects this to exist, so make sure it does:
	mkdir -p ${usbcpy}/os

	for zone in $CORE_ZONES
	do
	        # If the zone has a data dataset, copy to the path
		# create-zone.sh expects it for reuse.
		[ -f ${SDC_UPGRADE_DIR}/bu.tmp/${zone}/${zone}-data.zfs ] && \
		    cp ${SDC_UPGRADE_DIR}/bu.tmp/${zone}/${zone}-data.zfs \
			${usbcpy}/backup

	        ${usbcpy}/scripts/create-zone.sh ${zone} -w

	        # If we've copied the data dataset, remove it.  Also, we know
		# that create-zone will have restored the zone using the
		# copied zfs send stream.  Otherwise, if this zone has some
		# other form of backup, restore the zone now.
		if [[ -f ${usbcpy}/backup/${zone}-data.zfs ]]; then
			rm ${usbcpy}/backup/${zone}-data.zfs
		elif [[ -x ${usbcpy}/zones/${zone}/restore ]]; then
			${usbcpy}/zones/${zone}/restore ${zone} \
			    ${SDC_UPGRADE_DIR}/bu.tmp
		fi
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

# Use mapi to reprovision the extra zones.
function recreate_extra_zones
{
	NEW_EXTRA_ZONES=""

	local skip_boot=""
	for role in $ROLE_ORDER
	do
		# Check to see if we should install a zone with a given role
		match=0
		capi_convert=0
		for i in $ROLE_LIST
		do
			if [ $role == $i ]; then
				match=1
				break
			fi
		done

		# Checks for new roles that didn't exist in 6.5.
		# These checks need to work on post-6.5 too.

		# If we had capi, replace it with ufds.
		if [ $role == "ufds" -a $CAPI_FOUND == 1 ]; then
			match=1
			capi_convert=1
			# Change role for IP addr. lookup
			role="capi"
		fi

		# The OLD_STYLE_ZONES flag will be set if we're upgrading from
		# 6.5.x so we should install any brand new zones as well.
		if [ $match == 0 -a $OLD_STYLE_ZONES == 1 ]; then
			# We need to create all new zones that didn't
			# exist on 6.5.
			for i in $BRAND_NEW_ZONES
			do
				if [ $role == $i ]; then
					match=1
					break
				fi
			done
		fi

		[ $match == 0 ] && continue

		# Specify original IP address(es) (if we had that zone)
		ip_addrs=""
		[ -n "${ZONE_ADMIN_IP[$role]}" ] && \
		    ip_addrs="${ZONE_ADMIN_IP[$role]}"
		if [ -n "${ZONE_EXTERNAL_IP[$role]}" ]; then
			if [ -n "$ip_addrs" ]; then
		    		ip_addrs="$ip_addrs,${ZONE_EXTERNAL_IP[$role]}"
			else
		    		ip_addrs="${ZONE_EXTERNAL_IP[$role]}"
			fi
		fi

		unreserve_ip_addrs $role

		# Change role back to ufds
		[ $capi_convert == 1 ] && role="ufds"

		echo "Setup $role zone"
		reuse_ip_cmd=""
		[ -n "$ip_addrs" ] && reuse_ip_cmd="-I $ip_addrs"
		zname=`sdc-setup -c headnode $reuse_ip_cmd -r $role 2>&4 | \
		    nawk '{if ($1 == "New") print $3}'`

		if [ -z "$zname" ]; then
			echo "WARNING: failure setting up $role zone" \
			    >/dev/stderr
			continue
		fi

		NEW_EXTRA_ZONES="$zname $NEW_EXTRA_ZONES"

		# Wait up to 10 minutes for asynchronous role setup to finish
		echo "Wait for zone to finish seting up"
		local cnt=0
		while [ $cnt -lt 60 ]; do
			sleep 10
			[ -e /zones/$zname/root/var/svc/setup_complete ] && \
			    break
			cnt=$(($cnt + 1))
		done
		[ $cnt == 60 ] && \
		    echo "WARNING: setup did not finish after 10 minutes"

		# restore this zone from backup
		zoneadm -z $zname halt

		if [ -e  /usbkey/zones/$role/restore ]; then
			echo "Upgrading zone"
			/usbkey/zones/$role/restore $zname \
			    $SDC_UPGRADE_DIR/bu.tmp 1>&4 2>&1
		fi
		echo "$role zone done"

		# We need riak running to setup ufds
		if [ "$role" == "riak" ]; then
			zoneadm -z $zname boot
			skip_boot="$zname $skip_boot"
		fi

		# We need ufds running to convert capi data
		if [ "$role" == "ufds" ]; then
			zoneadm -z $zname boot
			skip_boot="$zname $skip_boot"

			# If moving from capi to ufds, convert capi.
			[ $CAPI_FOUND == 1 ] && convert_capi_ufds $zname
		fi
	done

	echo "Booting extra zones"
	for zone in $NEW_EXTRA_ZONES
	do
		# some zones already booted
		skip=0
		for i in $skip_boot
		do
			if [ "$zone" == "$i" ]; then
				skip=1
				break
			fi
		done
		[ $skip == 1 ] && continue
		zoneadm -z $zone boot
	done

	rm -rf $SDC_UPGRADE_DIR/bu.tmp
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
	agents=`ls -t /usbkey/ur-scripts | head -1`
	echo "Installing agents $agents"
	bash /usbkey/ur-scripts/$agents 1>&4 2>&1
}

rm -rf $SDC_UPGRADE_SAVE
mkdir -p $SDC_UPGRADE_SAVE

# Make sure we can talk to the old MAPI
curl -s -u admin:$CONFIG_mapi_http_admin_pw \
    http://$CONFIG_mapi_admin_ip/servers >/tmp/sdc$$.out 2>&1
check_mapi_err
rm -f /tmp/sdc$$.out
[ -n "$emsg" ] && fatal "MAPI API is not responding"

get_sdc_zonelist
get_sdc_datasets

if [ $RIAK_FOUND == 1 ]; then
	message="
We will be upgrading RIAK.  If you have other nodes in the RIAK cluster, you
must now stop riak on those nodes and detach them from the cluster.  You should
run the following commands in all of the other non-local RIAK zones:

    riak-admin leave
    riak stop

After you have finished detaching the non-local RIAK zones,
press [enter] to continue. "

	printf "$message"
	read continue;
fi

if [ $CAPI_FOUND == 1 ]; then
	# If we had a capi zone but no riak zone on the headnode, then we
	# won't be able to convert since the old 6.5 capi data is now stored
	# in riak.
	if [ $RIAK_FOUND == 0 ]; then
		message="
WARNING: A capi zone exists on this headnode but there is no riak zone.
         A local riak zone is required to automatically migrate the CAPI data
         forward into RIAK for UFDS.  The CAPI data will be dumped into
         $SDC_UPGRADE_SAVE/capi_dump.
         You will have to manually load this data into RIAK to complete the
         upgrade.

Press [enter] to continue "
		printf "$message"
		read continue;
	fi

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

# Can't shutdown core zones yet since we need those to delete MAPI provisioned
# zones in delete_new_sdc_zones.  We also can't shutdown old-style zones
# since they need to be running for sdc-backup to work on 6.5.
shutdown_non_core_zones

# Run full backup with the old sdc-backup code, then unpack the backup archive.
# Unfortunately the 6.5 sdc-backup exits 1 even when it succeeds so check for
# existence of backup file.
echo "Creating a backup"
sdc-backup -d $SDC_UPGRADE_SAVE
bfile=`ls $SDC_UPGRADE_SAVE/backup-* 2>/dev/null`
[ -z "$bfile" ] && fatal "unable to make a backup"

mkdir $SDC_UPGRADE_DIR/bu.tmp
(cd $SDC_UPGRADE_DIR/bu.tmp; gzcat $bfile | tar xbf 512 -)

mount_usbkey

check_versions
backup_usbkey
upgrade_usbkey

upgrade_pools

# import new headnode datasets (used for new headnode zones)
import_datasets

umount_usbkey

echo "Cleaning up existing zones"
delete_new_sdc_zones
# Wait a bit for zone deletion to finish
sleep 10
shutdown_remaining_zones
delete_old_sdc_zones

cleanup_config
load_sdc_config

# We do the first part of installing the platform now so the new platform
# is available for the new code to run on via the lofs mounts below.
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
mount -F lofs -o ro /image/usr/lib/zones/zoneadmd /usr/lib/zones/zoneadmd

# All of the following are using libzonecfg so we need to stop them before we
# can lofs mount the new libzonecfg.
svcadm disable zones-monitoring
svcadm disable smartlogin
svcadm disable cainstsvc
svcadm disable zonetracker-v2
svcadm disable metadata
# wait a few seconds for these svcs to stop using libzonecfg
sleep 5
mount -F lofs -o ro /image/usr/lib/libzonecfg.so.1 /usr/lib/libzonecfg.so.1
svcadm enable metadata
svcadm enable zonetracker-v2
# leave the other svcs disabled until reboot

# We restore the core zones as a side-effect during creation.
recreate_core_zones

# Wait till core zones are up before we try to import datasets.
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

# Now that MAPI is back up, register the new platform with mapi
register_platform

import_sdc_datasets

upgrade_agents

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

/usbkey/scripts/switch-platform.sh ${platformversion} 1>&4 2>&1

# Leave headnode setup for compute node upgrades of all roles
for role in $ROLE_ORDER
do
	assetdir=/zones/assets/root/assets/extra/$role
        mkdir -p $assetdir
        cp /usbkey/zones/$role/* $assetdir
        cp /usbkey/config $assetdir/hn_config
        cp /usbkey/config.inc/generic $assetdir/hn_generic
done
assetdir=/zones/assets/root/assets/extra/upgrade
rm -rf $assetdir
mkdir -p $assetdir
cp upgrade_cn $assetdir
cp /usbkey/ur-scripts/$agents $assetdir/agents.sh
cat /usbkey/config /usbkey/config.inc/generic >$assetdir/config

message="
The new image has been activated. You must reboot the system for the upgrade
to take effect.  Once you have verified the upgrade is ok, you can remove the
$SDC_UPGRADE_SAVE directory and its contents.\n\n"
printf "$message"

cp /tmp/perform_upgrade.* $SDC_UPGRADE_SAVE
exit 0
