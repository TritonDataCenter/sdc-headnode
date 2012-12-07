#!/bin/bash
#
# Copyright (c) 2012 Joyent Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin:/sbin
export PATH

MIN_SWAP=2
DEFAULT_SWAP=0.25x

# status output goes to /dev/console instead of stderr
exec 4>/dev/console

set -o errexit
set -o pipefail
set -o xtrace

# bump to line past console login prompt
echo "" >&4

#
# Load command line arguments in the form key=value (eg. swap=4g)
#
for p in $*; do
  k=$(echo "${p}" | cut -d'=' -f1)
  v=$(echo "${p}" | cut -d'=' -f2-)
  export arg_${k}=${v}
done

# Load SYSINFO_* and CONFIG_* values
. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

fatal()
{
    echo "Error: $1" >&4
    exit 1
}

function ceil
{
    x=$1

    # ksh93 supports a bunch of math functions that don't exist in bash.
    # including floating point stuff.
    expression="echo \$((ceil(${x})))"
    result=$(ksh93 -c "${expression}")

    echo ${result}
}

#
# Value can be in x (multiple of RAM) or g (GiB)
#
# eg: result=$(swap_in_GiB "0.25x")
#     result=$(swap_in_GiB "1.5x")
#     result=$(swap_in_GiB "2x")
#     result=$(swap_in_GiB "8g")
#
function swap_in_GiB
{
    swap=$(echo $1 | tr [:upper:] [:lower:])

    # Find system RAM for multiple
    RAM_MiB=${SYSINFO_MiB_of_Memory}
    RAM_GiB=$(ceil "${RAM_MiB} / 1024.0")

    swap_val=${swap%?}      # number
    swap_arg=${swap#${swap%?}}  # x or g

    result=
    case ${swap_arg} in
        x)
        result=$(ceil "${swap_val} * ${RAM_GiB}")
    ;;
        g)
        result=${swap_val}
    ;;
        *)
        echo "Unhandled swap argument: '${swap}'"
        return 1
    ;;
    esac

    if [[ -n ${result} ]]; then
        if [[ ${result} -lt ${MIN_SWAP} ]]; then
            echo ${MIN_SWAP}
        else
            echo ${result}
        fi
    fi

    return 0
}

function create_zpool
{
	SYS_ZPOOL="$1"
	POOL_JSON="$2"

	if ! /usr/sbin/zpool list -H -o name $SYS_ZPOOL; then
		printf "%-56s" "creating pool: $SYS_ZPOOL" >&4
		if ! /usr/bin/mkzpool ${SYS_ZPOOL} ${POOL_JSON}; then
			printf "%6s\n" "failed" >&4
			fatal "failed to create pool"
		fi

		#
		# XXX Workaround for OS-1745.  Setting this property causes
		# all labels to be updated, syncing up the txg numbers for
		# each vdev and ensuring we can later import.
		#
		zpool set comment="Joyent persistent store" $SYS_ZPOOL
	fi

	if ! zfs set atime=off ${SYS_ZPOOL}; then
		printf "%6s\n" "failed" >&4
		fatal "failed to set atime=off for pool ${SYS_ZPOOL}"
	fi

	printf "%4s\n" "done" >&4

	svccfg -s svc:/system/smartdc/init setprop config/zpool=${SYS_ZPOOL}
	svccfg -s svc:/system/smartdc/init:default refresh

	export CONFDS=${SYS_ZPOOL}/config
	export COREDS=${SYS_ZPOOL}/cores
	export OPTDS=${SYS_ZPOOL}/opt
	export VARDS=${SYS_ZPOOL}/var
	export USBKEYDS=${SYS_ZPOOL}/usbkey
	export SWAPVOL=${SYS_ZPOOL}/swap

	#
	# We don't support more than one storage pool on the system, but some
	# software expects this for futureproofing reasons.
	#
	touch /${SYS_ZPOOL}/.system_pool
}

#
# Create a dump device zvol on persistent storage.  The dump device is sized at
# 50% of the available physical memory.  Only kernel pages (so neither ARC nor
# user data) are included in the dump, and since those pages are compressed
# using bzip, it's basically impossible for the dump device to be too small.
#
create_dump()
{
    local dumpsize=$(( ${SYSINFO_MiB_of_Memory} / 2 ))

    # Create the dump zvol
    zfs create -V ${dumpsize}mb ${SYS_ZPOOL}/dump || \
      fatal "failed to create the dump zvol"
}

#
# Setup the persistent datasets on the zpool.
#
setup_datasets()
{
  datasets=$(zfs list -H -o name | xargs)
  
  if ! echo $datasets | grep dump > /dev/null; then
    printf "%-56s" "Making dump zvol... " >&4
    create_dump
    printf "%4s\n" "done" >&4
  fi

  if ! echo $datasets | grep ${CONFDS} > /dev/null; then
    printf "%-56s" "Initializing config dataset for zones... " >&4
    zfs create ${CONFDS} || fatal "failed to create the config dataset"
    chmod 755 /${CONFDS}
    cp -p /etc/zones/* /${CONFDS}
    zfs set mountpoint=legacy ${CONFDS}
    printf "%4s\n" "done" >&4
  fi

  if ! echo $datasets | grep ${USBKEYDS} > /dev/null; then
    if is_headnode; then
        printf "%-56s" "Creating usbkey dataset... " >&4
        zfs create -o mountpoint=legacy ${USBKEYDS} || \
          fatal "failed to create the usbkey dataset"
        printf "%4s\n" "done" >&4
    fi
  fi

  if ! echo $datasets | grep ${COREDS} > /dev/null; then
    printf "%-56s" "Creating global cores dataset... " >&4
    zfs create -o quota=10g -o mountpoint=/${SYS_ZPOOL}/global/cores \
        -o compression=gzip ${COREDS} || \
        fatal "failed to create the cores dataset"
    printf "%4s\n" "done" >&4
  fi

  if ! echo $datasets | grep ${OPTDS} > /dev/null; then
    printf "%-56s" "Creating opt dataset... " >&4
    zfs create -o mountpoint=legacy ${OPTDS} || \
      fatal "failed to create the opt dataset"
    printf "%4s\n" "done" >&4
  fi

  if ! echo $datasets | grep ${VARDS} > /dev/null; then
    printf "%-56s" "Initializing var dataset... " >&4
    zfs create ${VARDS} || \
      fatal "failed to create the var dataset"
    chmod 755 /${VARDS}
    cd /var
    if ( ! find . -print | cpio -pdm /${VARDS} 2>/dev/null ); then
        fatal "failed to initialize the var directory"
    fi

    zfs set mountpoint=legacy ${VARDS}
    printf "%4s\n" "done" >&4
  fi
}

create_swap()
{
    if [ -n "${arg_swap}" ]; then
        # From cmdline
        swapsize=$(swap_in_GiB ${arg_swap})
    elif [ -n "${CONFIG_swap}" ]; then
        # From config
        swapsize=$(swap_in_GiB ${CONFIG_swap})
    else
        # Fallback
        swapsize=$(swap_in_GiB ${DEFAULT_SWAP})
    fi

    if ! zfs list -H -o name ${SWAPVOL}; then
        printf "%-56s" "Creating swap zvol... " >&4

        #
	# We cannot allow the swap size to be less than the size of DRAM, lest
	# we run into the availrmem double accounting issue for locked
	# anonymous memory that is backed by in-memory swap (which will
	# severely and artificially limit VM tenancy).  We will therfore not
	# create a swap device smaller than DRAM -- but we still allow for the
	# configuration variable to account for actual consumed space by using
	# it to set the refreservation on the swap volume if/when the
	# specified size is smaller than DRAM.
        #
        minsize=$(swap_in_GiB 1x)

        if [[ $minsize -gt $swapsize ]]; then
            zfs create -V ${minsize}g ${SWAPVOL}
            zfs set refreservation=${swapsize}g ${SWAPVOL}
        else
            zfs create -V ${swapsize}g ${SWAPVOL}
        fi

        printf "%4s\n" "done" >&4
    fi
}

# We send info about the zpool when we have one, either because we created it or it already existed.
output_zpool_info()
{
    OLDIFS=$IFS
    IFS=$'\n'
    for line in $(zpool list -H -o name,guid,size,free,health); do
        name=$(echo "${line}" | awk '{ print $1 }')
        mountpoint=$(zfs get -H mountpoint ${SYS_ZPOOL} | awk '{ print $3 }')
        printf "${line}\t${mountpoint}\n"
    done
    IFS=$OLDIFS
}

# Loads config files for the node. These are the config values from the headnode
# plus authorized keys and anything else we want
install_configs()
{
    SMARTDC=/opt/smartdc/config/
    TEMP_CONFIGS=/var/tmp/node.config/

    # On standalone machines we don't get config in /var/tmp
    if [[ -n $(/usr/bin/bootparams | grep "^standalone=true") ]]; then
        return 0
    fi

    if ! is_headnode; then
        printf "%-56s" "Compute node, installing config files... " >&4
        if [[ ! -d $TEMP_CONFIGS ]]; then
            fatal "config files not present in /var/tmp"
        fi

        # mount /opt before doing this or changes are not going to be persistent
        mount -F zfs ${SYS_ZPOOL}/opt /opt || echo "/opt already mounted"

        mkdir -p /opt/smartdc/
        mv $TEMP_CONFIGS $SMARTDC
        printf "%4s\n" "done" >&4

        # re-load config here, since it will have just changed
        # (also location will be detected properly now)
        SDC_CONFIG_FILENAME=
        load_sdc_config
    fi
}

is_headnode()
{
	if [[ -z "$__headnode_known" ]]; then
		__headnode_bp="$(/usr/bin/bootparams | grep "^headnode=true")"
		__headnode_known=true
	fi
	if [[ -z "$__headnode_bp" ]]; then
		return 1	# "failure" == false == 1
	else
		return 0	# "success" == true == 0
	fi
}

create_vg()
{
    disks=
    for disk in $(sysinfo -p | grep "^Disk_.*_size" | cut -d'_' -f2); do
        pvcreate --zero y --metadatasize 1018k /dev/${disk}
	disks="${disks} /dev/${disk}"
    done

    vgcreate smartdc ${disks}
}

create_lvm_datasets()
{
    printf "%-56s" "Creating global cores dataset... " >&4
    lvcreate -L 5G -n cores smartdc
    mkfs.ext3 /dev/smartdc/cores
    mkdir -p /cores
    mount -text3 /dev/smartdc/cores /cores
    chmod 1777 /cores
    echo '/cores/core.%t.%u.%g.%s.%s' >/proc/sys/kernel/core_pattern
    printf "%4s\n" "done" >&4

    printf "%-56s" "Creating opt dataset... " >&4
    lvcreate -L 5G -n opt smartdc
    mkfs.ext3 /dev/smartdc/opt
    mount -text3 /dev/smartdc/opt /opt
    printf "%4s\n" "done" >&4

    printf "%-56s" "Initializing var dataset... " >&4
    lvcreate -L 5G -n var smartdc
    mkfs.ext3 /dev/smartdc/var
    mount -text3 /dev/smartdc/var /mnt
    (cd /var && tar -cpf - ./) | (cd /mnt && tar -xf -)
    umount /mnt
    mount -text3 /dev/smartdc/var /var
    printf "%4s\n" "done" >&4

    printf "%-56s" "Initializing vms dataset... " >&4
    mkdir -p /etc/vms
    lvcreate -L 1G -n vms smartdc
    mkfs.ext3 /dev/smartdc/vms
    mount -text3 /dev/smartdc/vms /etc/vms
    printf "%4s\n" "done" >&4
}

output_vg_info()
{
    results=$(vgs --separator '	' --units G --noheadings -o vg_name,vg_uuid,vg_size,vg_free | sed -e "s/^[ 	]*//")
    name=$(echo "${results}" | cut -d'	' -f1)
    echo "${results}	ONLINE	/${name}"
}

if [[ "$(zpool list)" == "no pools available" ]]; then
    if ! /usr/bin/disklayout "${arg_disklayout}" > /tmp/pool.json; then
	fatal "disk layout failed"
    fi

    create_zpool zones /tmp/pool.json
    setup_datasets
    install_configs
    create_swap
    output_zpool_info
    if ! is_headnode; then
        # If we're a non-headnode we exit with 113 which is a special code that tells ur-agent to:
        #
        #   1. pretend we exited with status 0
        #   2. send back the response to rabbitmq for this job
        #   3. reboot
        #
        exit 113
    fi
else
    output_zpool_info
fi

exit 0
