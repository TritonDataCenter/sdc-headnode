#!/bin/bash
#
# Copyright (c) 2012, Joyent, Inc., All rights reserved.
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
PATH=/usr/bin:/usr/sbin:/image/usr/sbin:/opt/smartdc/bin:/smartdc/bin
export PATH

BASH_XTRACEFD=4
set -o xtrace

ROOT=$(pwd)
export SDC_UPGRADE_DIR=/var/upgrade_headnode

# XXX fix this for oldest supported version
# We use the 6.5.4 USB key image build date to check the minimum
# upgradeable version.
VERS_6_5_4=20120523

ZONES6X="adminui assets billapi ca capi cloudapi dhcpd mapi portal rabbitmq riak"

mounted_usb="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' \
    svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' \
    svc:/system/filesystem/smartdc:default)"

. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

SAW_ERROR=0

message_ok="
The new image has been activated. You must reboot the system for the upgrade
to take effect.  Once you have verified the upgrade is ok, you can remove the
backup file in $SDC_UPGRADE_DIR.\n\n"

message_err="
ERROR: There were errors during the upgrade. You must review the upgrade
log (/tmp/perform_upgrade.*.log) and resolve the problems reported there before
you reboot the system. There is a backup file in $SDC_UPGRADE_DIR.\n\n"

function cleanup
{
    if [[ ${mounted_usb} == "true" ]]; then
        umount ${usbmnt}
        mounted_usb="false"
    fi

message_term="
ERROR: The upgrade process terminated prematurely and the system is in an
unknown state. You must review the upgrade log (/tmp/perform_upgrade.*.log)
to determine how to proceed.  There is a backup file in $SDC_UPGRADE_DIR.\n\n"

    [[ $SAW_ERROR == 1 ]] && printf "$message_err"
    printf "$message_term"

    cd /
    tar cbf 512 - tmp/*log*  | \
        gzip >$SDC_UPGRADE_DIR/logs.$(date -u +%Y%m%dT%H%M%S).tgz
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

function fatal
{
    msg=$1

    echo "ERROR: ${msg}" >/dev/stderr
    exit 1
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
    # When this compute node was first setup, it may have had an incorrect dump
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

function upgrade_zfs_datasets
{
    #
    # Certain template datasets were created with ZFS on-disk version 1.  Find
    # those datasets and upgrade them to the latest version.
    #
    zfs upgrade -a
}

function check_capi
{
    CAPI_FOUND=0

    for zone in `zoneadm list -cp | cut -f2 -d:`
    do
        # Remember we saw the capi zone so we can convert to ufds later.
        [[ "$zone" == "capi" ]] && CAPI_FOUND=1
    done
}

function dump_capi
{
    zstate=`zoneadm -z capi list -p | cut -d: -f3`
    [ "$zstate" != "running" ] && fatal "the capi zone must be running"

    echo "Dump CAPI for database conversion"
    mkdir -p $SDC_UPGRADE_DIR/capi_dump
    tables=`zlogin capi /opt/local/bin/psql -h127.0.0.1 -Upostgres -w \
        -Atc '\\\dt' capi | cut -d '|' -f2`
    for i in $tables
    do
        zlogin capi /opt/local/bin/pg_dump -Fp -w -a -EUTF-8 -Upostgres \
            -h127.0.0.1 -t $i capi >$SDC_UPGRADE_DIR/capi_dump/$i.dump
        [ $? != 0 ] && fatal "dumping the CAPI database"
    done

    shutdown_zone capi

    echo "Transforming CAPI postgres dumps to LDIF"
    $ROOT/capi2ldif.sh $SDC_UPGRADE_DIR/capi_dump \
        > $SDC_UPGRADE_DIR/capi_dump/ufds.ldif
    [ $? != 0 ] && fatal "transforming the CAPI dumps"
}

function dump_mapi
{
    zstate=`zoneadm -z mapi list -p | cut -d: -f3`
    [ "$zstate" != "running" ] && fatal "the mapi zone must be running"

    echo "Dump MAPI for database conversion"
    mkdir -p $SDC_UPGRADE_DIR/mapi_dump
    tables=`zlogin mapi /opt/local/bin/psql -Upostgres -w -Atc '\\\dt' mapi | \
        cut -d '|' -f2`
    for i in $tables
    do
        zlogin mapi /opt/local/bin/pg_dump -Fp -w -a -EUTF-8 -Upostgres \
            -t $i mapi \ >$SDC_UPGRADE_DIR/mapi_dump/$i.dump
        [ $? != 0 ] && fatal "dumping the MAPI database"
    done

    shutdown_zone mapi
}

function dump_riak
{
    zstate=`zoneadm -z riak list -p | cut -d: -f3`
    [ "$zstate" != "running" ] && fatal "the riak zone must be running"

    echo "Dump Riak for database conversion"
    $ROOT/dmp_riak $SDC_UPGRADE_DIR/riak_dump
    [ $? != 0 ] && fatal "dumping the Riak database"

    shutdown_zone riak
}

function shutdown_zone
{
	echo "Shutting down zone: $1"
	zlogin $1 /usr/sbin/shutdown -y -g 0 -i 5 1>&4 2>&1

	# Check for zone being down and halt it forcefully if needed
	local cnt=0
	while [ $cnt -lt 18 ]; do
		sleep 5
		local zstate=`zoneadm -z $1 list -p | cut -f3 -d:`
		[ "$zstate" == "installed" ] && break
		cnt=$(($cnt + 1))
	done

	# After 90 seconds, shutdown harder
	if [ $cnt == 18 ]; then
		echo "Forced shutdown of zone: $1"
		zlogin $1 svcs 1>&4 2>&1
		ps -fz $1 1>&4 2>&1
		zoneadm -z $1 halt
	fi
}

# Shutdown all core zones.
function shutdown_sdc_zones
{
	for zone in $ZONES6X
	do
		[[ "$zone" == "capi" && $CAPI_FOUND == 0 ]] && continue

		# skip zone that is already shutdown
    		zstate=`zoneadm -z $zone list -p | cut -d: -f3`
		[ "$zstate" == "installed" ] && continue

		shutdown_zone $zone
	done
}

function check_versions
{
	new_version=$(cat ${ROOT}/VERSION)

	existing_version=$(cat ${usbmnt}/version 2>/dev/null)
	[[ -z ${existing_version} ]] && \
	    fatal "unable to find version file in ${usbmnt}"

	# Check version to ensure it's possible to apply this update.
	# We only support upgrading from 6.5.4 or later builds.  The 6.5.4
	# build date is in the version string and hardcoded in this script.
	v_old=`echo $existing_version | \
	    nawk -F. '{split($1, f, "T"); print f[1]}'`
	[ $v_old -lt $VERS_6_5_4 ] && \
	    fatal "the system must be running at least SDC 6.5.4 to be upgraded"

	printf "Upgrading from %s\n            to %s\n" \
	    ${existing_version} ${new_version}
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
    [[ $? != 0 ]] && fatal "USB key backup failed"
}

function upgrade_usbkey
{
    echo "Upgrading the USB key"

    # Remove obsolete system-zone info
    rm -rf ${usbmnt}/zones/* /usbkey/zones/*

    local usbupdate=$(ls ${ROOT}/usbkey/*.tgz | tail -1)
    (cd ${usbmnt} && gzcat ${usbupdate} | gtar --no-same-owner -xf -)
    [ $? != 0 ] && SAW_ERROR=1

    (cd ${usbmnt} && rsync -a --exclude private --exclude os * ${usbcpy})
    [ $? != 0 ] && SAW_ERROR=1
}

function delete_sdc_zones
{
	for zone in $ZONES6X
	do
		[[ "$zone" == "capi" && $CAPI_FOUND == 0 ]] && continue

		echo "Deleting zone: $zone"
		zoneadm -z $zone uninstall -F
		[ $? != 0 ] && SAW_ERROR=1
		zonecfg -z $zone delete -F
		[ $? != 0 ] && SAW_ERROR=1
	done
}

# Converts an IP and netmask to a network
# For example: 10.99.99.7 + 255.255.255.0 -> 10.99.99.0
# Each field is in the net_a, net_b, net_c and net_d variables.
# Also, host_addr stores the address of the host w/o the network number (e.g.
# 7 in the 10.99.99.7 example above).
ip_netmask_to_haddr()
{
	IP=$1
	NETMASK=$2

	OLDIFS=$IFS
	IFS=.
	set -- $IP
	net_a=$1
	net_b=$2
	net_c=$3
	net_d=$4
	addr_d=$net_d

	set -- $NETMASK
	net_a=$(($net_a & $1))
	net_b=$(($net_b & $2))
	net_c=$(($net_c & $3))
	net_d=$(($net_d & $4))
	host_addr=$(($addr_d & ~$4))

	IFS=$OLDIFS
}

# Fix up the USB key config file
function cleanup_config
{
	echo "Cleaning up configuration"
	mount_usbkey

	cat <<-SED_DONE >/tmp/upg.$$
	/^adminui_admin_ip=/d
	/^adminui_external_ip=/d
	/^assets_admin_ip=/d
	/^ca_admin_ip=/d
	/^ca_client_url=/d
	/^capi_/d
	/^dhcpd_admin_ip=/d
	/^dhcp_next_server=/d
	/^mapi_/d
	/^portal_external_ip=/d
	/^portal_external_url=/d
	/^cloudapi_admin_ip=/d
	/^cloudapi_external_ip=/d
	/^cloudapi_external_url=/d
	/^rabbitmq_admin_ip=/d
	/^rabbitmq=/d
	/^riak_admin_ip=/d
	/^billapi_admin_ip=/d
	/^billapi_external_ip=/d
	/^billapi_external_url=/d
	/^mapi_datasets=/d
	/^# This should not be changed/d
	/^initial_script=/d
	SED_DONE

	sed -f /tmp/upg.$$ </mnt/usbkey/config >/tmp/config.$$

	# Calculate fixed addresses for some of the new zones
	# Using the model from the 6.x prompt-config.sh we use the old
	# assets_admin_ip address as the starting point for the zones and
	# increment up.
	# XXX should really start from the adminui_admin_ip address?
	# This address is being removed from the config and not in the new one.
	ip_netmask_to_haddr "$CONFIG_assets_admin_ip" "$CONFIG_admin_netmask"
	next_addr=$host_addr
	assets_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	dhcpd_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	napi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	zookeeper_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	moray_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	ufds_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	workflow_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	rabbitmq_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	cnapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	dapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	next_addr=$(expr $next_addr + 1)
	vmapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

	cat <<-DONE >>/tmp/config.$$

	assets_admin_ip=$assets_admin_ip
	assets_admin_ips=$assets_admin_ip
	dhcpd_admin_ip=$dhcpd_admin_ip
	dhcpd_admin_ips=$dhcpd_admin_ip
	rabbitmq_admin_ip=$rabbitmq_admin_ip
	rabbitmq_admin_ips=$rabbitmq_admin_ip
	rabbitmq=guest:guest:${rabbitmq_admin_ip}:5672

	zookeeper_root_pw=$CONFIG_adminui_root_pw
	zookeeper_admin_ips=$zookeeper_admin_ip

	moray_root_pw=$CONFIG_adminui_root_pw
	moray_admin_ips=$moray_admin_ip

	ufds_root_pw=$CONFIG_adminui_root_pw
	ufds_admin_ips=$ufds_admin_ip

	workflow_root_pw=$CONFIG_adminui_root_pw
	workflow_admin_ips=$workflow_admin_ip

	cnapi_root_pw=$CONFIG_adminui_root_pw
	cnapi_admin_ips=$cnapi_admin_ip

	dapi_root_pw=$CONFIG_adminui_root_pw
	dapi_admin_ips=$dapi_admin_ip

	vmapi_root_pw=$CONFIG_adminui_root_pw
	vmapi_admin_ips=$vmapi_admin_ip

	amon_root_pw=$CONFIG_adminui_root_pw
	amon_admin_pw=$CONFIG_adminui_admin_pw

	redis_root_pw=$CONFIG_adminui_root_pw
	redis_admin_pw=$CONFIG_adminui_admin_pw

	ufds_is_local=$CONFIG_capi_is_local
	# ufds_external_vlan=0
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

	# vmapi_external_vlan=0
	vmapi_root_pw=$CONFIG_adminui_root_pw
	vmapi_http_admin_user=admin
	vmapi_http_admin_pw=$CONFIG_adminui_admin_pw

	# dapi_external_vlan=0
	dapi_root_pw=$CONFIG_adminui_root_pw
	dapi_http_admin_user=admin
	dapi_http_admin_pw=$CONFIG_adminui_admin_pw

	# cnapi_external_vlan=0
	cnapi_root_pw=$CONFIG_adminui_root_pw
	cnapi_http_admin_user=admin
	cnapi_http_admin_pw=$CONFIG_adminui_admin_pw
	cnapi_client_url=http://${cnapi_admin_ip}:80

	# napi_external_vlan=0
	napi_root_pw=$CONFIG_adminui_root_pw
	napi_http_admin_user=admin
	napi_http_admin_pw=$CONFIG_adminui_admin_pw
	napi_admin_ips=$napi_admin_ip
	napi_client_url=http://${napi_admin_ip}:80
	napi_mac_prefix=90b8d0

	workflow_root_pw=$CONFIG_adminui_root_pw
	workflow_admin_pw=$CONFIG_adminui_admin_pw
	workflow_http_admin_user=admin
	workflow_http_admin_pw=$CONFIG_adminui_admin_pw

	dcapi_root_pw=$CONFIG_adminui_root_pw
	dcapi_http_admin_user=admin
	dcapi_http_admin_pw=$CONFIG_adminui_admin_pw

	show_setup_timers=true
	serialize_setup=true
	DONE

	cp /tmp/config.$$ /mnt/usbkey/config
 	cp /mnt/usbkey/config /usbkey/config

	rm -f /tmp/config.$$ /tmp/upg.$$

	# Load the new pkg values from the upgrade conf.generic into variables.
	eval $(cat ${ROOT}/conf.generic | sed -e "s/^ *//" | grep -v "^#" | \
	    grep "^[a-zA-Z]" | sed -e "s/^/GENERIC_/")

	pkgs=`set | nawk -F=  '/^GENERIC_pkg_/ {print $2}'`

	# Convert generic config
	# Remove obsolete entries and adjust the core-zone memory caps
	# in the generic file
	cat <<-SED_DONE >/tmp/upg.$$
		/^adminui_cpu_shares/d
		/^adminui_max_lwps/d
		/^adminui_memory_cap/d
		/^dhcpd_cpu_shares/d
		/^dhcpd_max_lwps/d
		/^dhcpd_memory_cap/d
		/^assets_/d
		/^billapi_/d
		/^ca_/d
		/^capi_/d
		/^cloudapi_/d
		/^mapi_/d
		/^portal_/d
		/^rabbitmq_/d
		/^riak_/d
		/^sdc_version/d
		/^# If the capi_allow_file/d
		/^# CIDR addresses like:/d
		/^# 10.99.99.0\/24/d
		/^# 10.88.88.0\/24/d
		/^# These networks are then the/d
		/^# this file existing and being populated/d
	SED_DONE

	sed -f /tmp/upg.$$ </mnt/usbkey/config.inc/generic \
	    >/tmp/config.$$

	# add all pkg_ entries from upgrade generic file
	echo "" >>/tmp/config.$$
	echo "# Pkg entry format:" >>/tmp/config.$$
	echo "#        name:ram:swap:disk:cap:nlwp:iopri" >>/tmp/config.$$
	echo "#" >>/tmp/config.$$
	echo "# These must start with 0 and increment by 1." >>/tmp/config.$$
	cnt=0
	for i in $pkgs
	do
		echo "pkg_$cnt=$i" >>/tmp/config.$$
		cnt=$((cnt + 1))
	done

	# add new entries
	cat <<-DONE >>/tmp/config.$$

	initial_script=scripts/headnode.sh

	# Positive offset from UTC 0. Used to calculate cron job start times.
	utc_offset=0

	adminui_pkg=${GENERIC_adminui_pkg}
	amon_pkg=${GENERIC_amon_pkg}
	assets_pkg=${GENERIC_assets_pkg}
	billapi_pkg=${GENERIC_billapi_pkg}
	ca_pkg=${GENERIC_ca_pkg}
	cloudapi_pkg=${GENERIC_cloudapi_pkg}
	cnapi_pkg=${GENERIC_cnapi_pkg}
	dapi_pkg=${GENERIC_dapi_pkg}
	dcapi_pkg=${GENERIC_dcapi_pkg}
	dhcpd_pkg=${GENERIC_dhcpd_pkg}
	moray_pkg=${GENERIC_moray_pkg}
	napi_pkg=${GENERIC_napi_pkg}
	portal_pkg=${GENERIC_portal_pkg}
	rabbitmq_pkg=${GENERIC_rabbitmq_pkg}
	redis_pkg=${GENERIC_redis_pkg}
	ufds_pkg=${GENERIC_ufds_pkg}
	workflow_pkg=${GENERIC_workflow_pkg}
	vmapi_pkg=${GENERIC_vmapi_pkg}
	zookeeper_pkg=${GENERIC_zookeeper_pkg}
	DONE

	cp /tmp/config.$$ /mnt/usbkey/config.inc/generic
	cp /mnt/usbkey/config.inc/generic /usbkey/config.inc/generic
	rm -f /tmp/config.$$ /tmp/upg.$$

	umount_usbkey
}

# Transform CAPI pg_dumps into LDIF, then load into UFDS
# capi dump files are in $SDC_UPGRADE_DIR/capi_dump
function convert_capi_ufds
{
	echo "Transforming CAPI postgres dumps to LDIF."
	${usbcpy}/scripts/capi2ldif.sh ${SDC_UPGRADE_DIR}/capi_dump \
	    > $SDC_UPGRADE_DIR/capi_dump/ufds.ldif
	[ $? != 0 ] && SAW_ERROR=1

	# We're on the headnode, so we know the zonepath is in /zones.
	cp $SDC_UPGRADE_DIR/capi_dump/ufds.ldif /zones/$1/root

	# Wait up to 2 minutes for ufds zone to be ready
	echo "Waiting for ufds zone to finish booting"
	local cnt=0
	while [ $cnt -lt 12 ]; do
		sleep 10
		local scnt=`svcs -z $1 -x 2>/dev/null | wc -l`
		[ $scnt == 0 ] && break
		cnt=$(($cnt + 1))
	done
	if [ $cnt == 12 ]; then
		echo "WARNING: some ufds svcs still not ready after 2 minutes"
		SAW_ERROR=1
	fi

	# re-load config to pick up settings for newly created ufds zone
	load_sdc_config

	echo "Running ldapadd on transformed CAPI data"
	zlogin $1 LDAPTLS_REQCERT=allow /opt/local/bin/ldapadd \
	    -H ${CONFIG_ufds_client_url} \
	    -D ${CONFIG_ufds_ldap_root_dn} \
	    -w ${CONFIG_ufds_ldap_root_pw} \
	    -f /ufds.ldif 1>&4 2>&1
	[ $? != 0 ] && SAW_ERROR=1

	rm -f /zones/$1/root/ufds.ldif
}

# We expect the usbkey to already be mounted when we run this
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
	[ $? != 0 ] && \
	    fatal "unable to install the new platform onto the USB key"

	[[ -f ${usbmnt}/os/${platformversion}/platform/root.password ]] && \
	    mv -f ${usbmnt}/os/${platformversion}/platform/root.password \
		${usbmnt}/private/root.password.${platformversion}

	echo "Copying ${platformversion} to ${usbcpy}/os"
	mkdir -p ${usbcpy}/os
	(cd ${usbmnt}/os && \
	    rsync -a ${platformversion}/ ${usbcpy}/os/${platformversion})
	[ $? != 0 ] && \
	    fatal "unable to install the new platform onto the USB key"
}

function wait_and_clear
{
	while [ true ]; do
		# It seems like jobs -p can miscount if we don't run jobs first
		jobs >/dev/null
		local cnt=`jobs -p | wc -l`
		[ $cnt -eq 0 ] && break
		for s in `svcs -x | nawk '/^svc:/ {print $1}'`
		do
			svcadm clear $s
		done
		sleep 1
	done
}

# Ensure we're a SmartOS headnode
if [[ ${SYSINFO_Bootparam_headnode} != "true" \
    || $(uname -s) != "SunOS" \
    || -z ${SYSINFO_Live_Image} ]]; then

    fatal "this can only be run on a SmartOS headnode."
fi

mkdir -p $SDC_UPGRADE_DIR

mount_usbkey
check_versions
umount_usbkey

# Make sure there are no svcs in maintenance. This will break checking later
# in the upgrade process.
maint_svcs=`svcs -x | nawk '/^svc:/ BEGIN {cnt=0} {cnt++} END {print cnt}'`
[ $maint_svcs -gt 0 ] && \
    fatal "there are SMF svcs in maintenance, unable to proceed with upgrade."

trap cleanup EXIT

# Since we're upgrading from 6.x we cannot shutdown the zones before backing
# up, since 6.x backup depends on the zones running.

# Run full backup with the old sdc-backup code, then unpack the backup archive.
# Unfortunately the 6.5 sdc-backup exits 1 even when it succeeds so check for
# existence of backup file.
echo "Creating a backup"
sdc-backup -s datasets -d $SDC_UPGRADE_DIR
[[ $? != 0 ]] && fatal "unable to make a backup"
bfile=`ls $SDC_UPGRADE_DIR/backup-* 2>/dev/null`
[ -z "$bfile" ] && fatal "missing backup file"

# We shutdown the zones whose databases we're dumping, as we go along, so that
# the data provided by these zones won't change after the dump

check_capi
[ $CAPI_FOUND == 1 ] && dump_capi

dump_mapi

dump_riak

# Now we can shutdown the rest of the zones so we are in a more stable state
# for the rest of this phase of the upgrade.
shutdown_sdc_zones

mkdir $SDC_UPGRADE_DIR/bu.tmp
(cd $SDC_UPGRADE_DIR/bu.tmp; gzcat $bfile | tar xbf 512 -)

mount_usbkey

backup_usbkey

upgrade_pools
upgrade_zfs_datasets

install_platform

# At this point we start doing destructive actions on the HN, so we should
# no longer call "fatal" if we see an error.

upgrade_usbkey

umount_usbkey

echo "Deleting existing zones"
delete_sdc_zones

cleanup_config
load_sdc_config

/usbkey/scripts/switch-platform.sh ${platformversion} 1>&4 2>&1
[ $? != 0 ] && SAW_ERROR=1

# Remove 6.5.x agent manifests so that svcs won't fail when we boot onto 7.0
#
# This process is execessively complex but if not done carefully we will wedge
# with svcs in maintenance.  We start by removing all but the agents_core.
# Sometimes this leaves one or more agents still installed, so we do it again.
# Finally we remove the agents_core (which should be the only thing left) and
# then clean up the dirs so new agents will install into a fresh environment.
# The wait_and_clear function is used to watch for svcs goint into maintenance
# during this process and clear them so that the agent uninstall can continue.
echo "Deleting old agents"

AGENTS_DIR=/opt/smartdc/agents

TOREMOVE=`/opt/smartdc/agents/bin/agents-npm --no-registry ls installed \
    2>/dev/null | nawk '{print $1}'`
for agent in $TOREMOVE
do
    (echo "$agent" | egrep -s '^atropos@') && continue
    # We have to do agents_core after the others
    (echo "$agent" | egrep -s '^agents_core@') && continue

    # Supress possible npm warning removing CA (See AGENT-392)
    if (echo "$agent" | egrep -s '^cainstsvc'); then
        [ -e $AGENTS_DIR/smf/cainstsvc-default.xml ] && \
            touch $AGENTS_DIR/smf/cainstsvc.xml
    fi

    echo "Uninstall: $agent"
    /opt/smartdc/agents/bin/agents-npm uninstall $agent 1>&4 2>&1 &
    wait_and_clear
done

TOREMOVE=`/opt/smartdc/agents/bin/agents-npm --no-registry ls installed \
    2>/dev/null | nawk '{print $1}'`
for agent in $TOREMOVE
do
    (echo "$agent" | egrep -s '^atropos@') && continue
    # We have to do agents_core after the others
    (echo "$agent" | egrep -s '^agents_core@') && continue

    echo "Uninstall: $agent"
    /opt/smartdc/agents/bin/agents-npm uninstall $agent 1>&4 2>&1 &
    wait_and_clear
done

TOREMOVE=`/opt/smartdc/agents/bin/agents-npm --no-registry ls installed \
    2>/dev/null | nawk '{print $1}'`
for agent in $TOREMOVE
do
    (echo "$agent" | egrep -s '^atropos@') && continue

    echo "Uninstall: $agent"
    /opt/smartdc/agents/bin/agents-npm uninstall $agent 1>&4 2>&1 &
    wait_and_clear
done

for dir in $(ls "$AGENTS_DIR"); do
    case "$dir" in
    db|smf) continue ;;
    *)      rm -fr $AGENTS_DIR/$dir ;;
    esac
done

rm -rf $AGENTS_DIR/smf/*

# Fix up /var
mkdir -m755 -p /var/db/imgadm

cd /tmp
cp -pr *log* $SDC_UPGRADE_DIR

cp -pr $ROOT/upgrade_hooks.sh $SDC_UPGRADE_DIR
chmod +x $SDC_UPGRADE_DIR/upgrade_hooks.sh

trap EXIT

[[ $SAW_ERROR == 1 ]] && fatal "first pass of upgrade failed"

echo "Rebooting to finish the upgrade"
reboot
exit 0
