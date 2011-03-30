#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
#

PATH=/usr/bin:/usr/sbin
export PATH

ZPOOL=zones

CONFDS=$ZPOOL/config
COREDS=$ZPOOL/cores
OPTDS=$ZPOOL/opt
VARDS=$ZPOOL/var
USBKEYDS=$ZPOOL/usbkey
SWAPVOL=${ZPOOL}/swap
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

#
# find disk(s) - either 1 disk or multiple - maybe raidz?
#
create_zpool()
{
    disks=''

    if /usr/bin/bootparams | grep "headnode=true"; then
        for disk in `/usr/bin/disklist -n`; do
            # Only include disks that aren't mounted (so we skip USB Key)
            if ( ! grep ${disk} /etc/mnttab ); then
                disks="${disks} ${disk}"
            fi
        done
    else
        disks=`/usr/bin/disklist -n`
    fi

    disk_count=$(echo "${disks}" | wc -w | tr -d ' ')

    if [ ${disk_count} -lt 1 ]; then
        # XXX what if no disks found?
        fatal "no disks found, can't create zpool"
    elif [ ${disk_count} -eq 1 ]; then
        # create a zpool with a single disk
        zpool create ${ZPOOL} ${disks}
    else
        # if more than one disk, create a raidz zpool
        zpool create ${ZPOOL} raidz ${disks}
    fi
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
    base_size=`zfs get -H -p -o value available $ZPOOL`
    # Convert to MB
    base_size=`expr $base_size / 1000000`
    # Calculate 5% of that
    base_size=`expr $base_size / 20`
    # Cap it at 4GB
    [ ${base_size} -gt 4096 ] && base_size=4096

    # Create the dump zvol
    zfs create -V ${base_size}mb ${ZPOOL}/dump || \
      fatal "failed to create the dump zvol"
}

#
# Setup the persistent datasets on the zpool.
#
setup_datasets()
{
    echo -n "Making dump zvol... " >&4
    create_dump
    echo "done." >&4

    echo -n "Initializing config dataset for zones... " >&4
    zfs create ${CONFDS} || fatal "failed to create the config dataset"
    chmod 755 /${CONFDS}
    cp -p /etc/zones/* /${CONFDS}
    zfs set mountpoint=legacy ${CONFDS}
    echo "done." >&4

    if [[ -n $(/bin/bootparams | grep "^headnode=true") ]]; then
        echo -n "Creating usbkey dataset... " >&4
        zfs create -o mountpoint=legacy ${USBKEYDS} || \
          fatal "failed to create the usbkey dataset"
        echo "done." >&4
    fi

    echo -n "Creating global cores dataset... " >&4
    zfs create -o quota=10g -o mountpoint=/zones/global/cores \
        -o compression=gzip ${COREDS} || \
        fatal "failed to create the cores dataset"
    echo "done." >&4

    echo -n "Creating opt dataset... " >&4
    zfs create -o mountpoint=legacy ${OPTDS} || \
      fatal "failed to create the opt dataset"
    echo "done." >&4

    echo -n "Initializing var dataset... " >&4
    zfs create ${VARDS} || \
      fatal "failed to create the var dataset"
    chmod 755 /${VARDS}
    cd /var
    if ( ! find . -print | cpio -pdm /${VARDS} 2>/dev/null ); then
        fatal "failed to initialize the var directory"
    fi

    zfs set mountpoint=legacy ${VARDS}
    echo "done." >&4
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

    echo -n "Creating swap zvol... " >&4
    zfs create -V ${swapsize}g ${SWAPVOL}
    echo "done." >&4
}

# We send info about the zpool when we have one, either because we created it or it already existed.
output_zpool_info()
{
    OLDIFS=$IFS
    IFS=$'\n'
    for line in $(zpool list -H -o name,guid,size,free,health); do
        name=$(echo "${line}" | awk '{ print $1 }')
        mountpoint=$(zfs get -H mountpoint zones | awk '{ print $3 }')
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
        echo -n "Compute node, installing config files... " >&4
        if [[ ! -d $TEMP_CONFIGS ]]; then
            fatal "config files not present in /var/tmp"
        fi

        # mount /opt before doing this or changes are not going to be persistent
        mount -F zfs zones/opt /opt
        mkdir -p /opt/smartdc/
        mv $TEMP_CONFIGS $SMARTDC
        echo "done." >&4

        # re-load config here, since it will have just changed
        # (also location will be detected properly now)
        SDC_CONFIG_FILENAME=
        load_sdc_config
    fi
}

POOLS=`zpool list`
if [[ ${POOLS} == "no pools available" ]]; then
    create_zpool
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

exit 0
