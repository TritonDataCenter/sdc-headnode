#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin:/sbin:/bin
export PATH

MIN_SWAP=2
DEFAULT_SWAP=0.25x

# Fix staircase on Linux
if [[ $(uname -s) == 'Linux' ]]; then
    stty onlcr opost </dev/console >/dev/console 2>&1
fi

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

    if [[ $(uname -s) != 'Linux' ]]; then
        # ksh93 supports a bunch of math functions that don't exist in bash.
        # including floating point stuff.
        expression="echo \$((ceil(${x})))"
        result=$(ksh93 -c "${expression}")
    else
	# On SunOS we use ksh93, on Linux perl?!  Which is worse?
        result=$(perl -e "use POSIX qw/ceil/; my \$num = (${x}); print ceil(\$num) . \"\n\";")
    fi

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

#
# The arguments to joysetup will specify the disks and RAID profile to use.  If
# not specified, this script will create a single pool iff there is a single
# disk available.  In that case, the assumption is a hardware RAID card is
# managing the physical disks and has exposed only a single logical disk to the
# filesystem.  If more than one disk is available when no storage configuration
# is provided, then the number of disks determines the default profile.  A
# mirrored pool is created with two disks.  A RAID-Z pool is created with three
# or more disks.
#
# The arguments to joysetup specify the pool(s), disks for each pool, and 
# the profile of each pool (RAID-Z, mirrored, etc.).  An example:
#
#     pools=zones,tank
#     zones_disks=c0t0d0,c0t1d0
#     zones_profile=mirror
#     tank_disks=c1t0d0,c1t1d0,c1t2d0,c1t3d0,c1t4d0,c1t5d0,c1t6d0,c1t7d0
#     tank_profile=raidz
#
# Those arguments to joysetup specify a mirrored pool 'zones' with two disks,
# and a RAID-Z pool 'tank' with eight disks.
#
create_zpool()
{
    OLDIFS=$IFS
    unset IFS

    pool=$1

    if [[ -n $pool ]]; then
        disks=$(eval echo \${arg_${pool}_disks})
        disks=$(echo $disks | tr ',' ' ')
        profile=$(eval echo \${arg_${pool}_profile})
    fi

    # If the pool already exists, don't create it again.
    if /usr/sbin/zpool list -H -o name $pool; then
        return 0
    fi

    # If we're creating a pool for a headnode, or if a list of disks is not
    # specified for a pool, include all disks in the default pool.
    if /usr/bin/bootparams | grep "headnode=true" || [[ -z $disks ]]; then
        disks=
        for disk in `/usr/bin/disklist -n`; do
            # Only include disks that aren't mounted (so we skip USB Key)
            if ( ! grep ${disk} /etc/mnttab ); then
                disks="${disks} ${disk}"
            fi
        done
    fi

    disk_count=$(echo "${disks}" | wc -w | tr -d ' ')
    printf "%-56s" "Creating pool $pool... " >&4

    # If no pool profile was provided, use a default based on the number of
    # devices in that pool.
    if [[ -z ${profile} ]]; then
        case ${disk_count} in
        0)
             fatal "no disks found, can't create zpool";;
        1)
             profile="";;
        2)
             profile=mirror;;
        *)
             profile=raidz;;
        esac
    fi

    # The zpool command doesn't accept the 'striped' profile, but creates a
    # striped pool when no profile is specified.
    if [[ ${profile} == "striped" ]]; then
        profile=""
    fi

    zpool_args=""

    # When creating a mirrored pool, create a mirrored pair of devices out of
    # every two disks.
    if [[ ${profile} == "mirror" ]]; then
        ii=0
        for disk in ${disks}; do
            if [[ $(( $ii % 2 )) -eq 0 ]]; then
                  zpool_args="${zpool_args} ${profile}"
            fi
            zpool_args="${zpool_args} ${disk}"
            ii=$(($ii + 1))
        done
    else
        zpool_args="${profile} ${disks}"
    fi

    zpool create ${pool} ${zpool_args} || \
        fatal "failed to create pool ${pool}"
    zfs set atime=off ${pool} || \
        fatal "failed to set atime=off for pool ${pool}"

    printf "%4s\n" "done" >&4

    IFS=$OLDIFS
}

create_zpools()
{
    if /usr/bin/bootparams | grep "headnode=true"; then
        export SYS_ZPOOL=zones
        create_zpool ${SYS_ZPOOL}
    else
        if [[ -z "${arg_pools}" ]]; then
            export SYS_ZPOOL=zones
            create_zpool ${SYS_ZPOOL}
        else
            IFS=,
            for pool in ${arg_pools}; do
                create_zpool $pool
            done
            unset IFS

            export SYS_ZPOOL=$(echo $arg_pools | \
                sed 's/^\([a-zA-Z0-9]*\),.*/\1/')
        fi
    fi

    svccfg -s svc:/system/smartdc/init setprop config/zpool=${SYS_ZPOOL}
    svccfg -s svc:/system/smartdc/init:default refresh

    export CONFDS=${SYS_ZPOOL}/config
    export COREDS=${SYS_ZPOOL}/cores
    export OPTDS=${SYS_ZPOOL}/opt
    export VARDS=${SYS_ZPOOL}/var
    export USBKEYDS=${SYS_ZPOOL}/usbkey
    export SWAPVOL=${SYS_ZPOOL}/swap

    #
    # Since there may be more than one storage pool on the system, put a
    # file with a certain name in the actual "system" pool.
    #
    touch /${SYS_ZPOOL}/.system_pool
}

#
# XXX - may want to tweak this algorithm a bit (needs to work in production
# and on coal)
# Create a dump device zvol on persistent storage.  Make it either 5% of the
# base ZFS dataset size or 4GB, whichever is less.
#
create_dump()
{
    # Get avail zpool size - this assumes we're not using any space yet.
    base_size=`zfs get -H -p -o value available ${SYS_ZPOOL}`
    # Convert to MB
    base_size=`expr $base_size / 1000000`
    # Calculate 5% of that
    base_size=`expr $base_size / 20`
    # Cap it at 4GB
    [ ${base_size} -gt 4096 ] && base_size=4096

    # Create the dump zvol
    zfs create -V ${base_size}mb ${SYS_ZPOOL}/dump || \
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
    if [[ -n $(/bin/bootparams | grep "^headnode=true") ]]; then
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

    if [[ $(uname -s) == 'Linux' ]]; then
        printf "%-56s" "Creating swap volume... " >&4
        lvcreate -L ${swapsize}G -n swap smartdc
        mkswap -f /dev/smartdc/swap
        swapon /dev/smartdc/swap
    else
        if ! zfs list -H -o name ${SWAPVOL}; then
            printf "%-56s" "Creating swap zvol... " >&4
            zfs create -V ${swapsize}g ${SWAPVOL}
            printf "%4s\n" "done" >&4
        fi
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

    if [[ -z $(/usr/bin/bootparams | grep "^headnode=true") ]]; then
        printf "%-56s" "Compute node, installing config files... " >&4
        if [[ ! -d $TEMP_CONFIGS ]]; then
            fatal "config files not present in /var/tmp"
        fi

        # mount /opt before doing this or changes are not going to be persistent
        if [[ $(uname -s) != 'Linux' ]]; then
            mount -F zfs ${SYS_ZPOOL}/opt /opt || echo "/opt already mounted"
        fi
        mkdir -p /opt/smartdc/
        mv $TEMP_CONFIGS $SMARTDC
        printf "%4s\n" "done" >&4

        # re-load config here, since it will have just changed
        # (also location will be detected properly now)
        SDC_CONFIG_FILENAME=
        load_sdc_config
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

if [[ $(uname -s) == 'Linux' ]]; then
    if [[ -z $(vgs) ]]; then

        # TODO: see if we can tell if there's a zpool, if so, fail.

        # rpool   7786468255783555057     278G    21.9G   ONLINE  /rpool
        create_vg
        create_lvm_datasets
        install_configs
        create_swap
        output_vg_info
        # We exit with 113 which is a special code that tells ur-agent to:
        #
        #   1. pretend we exited with status 0
        #   2. send back the response to rabbitmq for this job
        #   3. reboot
        #
        exit 113
    else
        output_vg_info
    fi
else
    POOLS=`zpool list`
    if [[ ${POOLS} == "no pools available" ]]; then
        create_zpools
        setup_datasets
        install_configs
        create_swap
        output_zpool_info
        if [[ -z $(/usr/bin/bootparams | grep "headnode=true") ]]; then
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
fi

exit 0
