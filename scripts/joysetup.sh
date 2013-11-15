#!/bin/bash
#
# Copyright (c) 2012 Joyent Inc., All rights reserved.
#
# The first script to setup a node (aka server) for SDC. For CNs this is
# run via the ur agent.
#
# WARNING: YOU DO NOT HAVE INTERNET ACCESS IN THIS ENVIRONMENT! DO NOT RELY
# ON IT!
#

PATH=/usr/bin:/usr/sbin:/sbin
export PATH

MIN_SWAP=2
DEFAULT_SWAP=0.25x
TEMP_CONFIGS=/var/tmp/node.config

#
# Servers must have twice as much available disk space as RAM for setup
# to run successfully.
#
MIN_DISK_TO_RAM=2

# status output goes to /dev/console instead of stderr
exec 4>/dev/console

# keep a copy of the output in /tmp/joysetup.$$ for later viewing
exec > >(tee /tmp/joysetup.$$)
exec 2>&1

set -o errexit
set -o pipefail
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
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

# Mock CN is used for creating "fake" Compute Nodes in SDC for testing.
MOCKCN=
if [[ $(zonename) != "global" && -n ${MOCKCN_SERVER_UUID} ]]; then
    export SDC_CONFIG_FILENAME="/mockcn/${MOCKCN_SERVER_UUID}/node.config"
    MOCKCN="true"
fi

# Load SYSINFO_* and CONFIG_* values
. /lib/sdc/config.sh
load_sdc_sysinfo
load_sdc_config

# flag set when we're on a 6.x platform
ENABLE_6x_WORKAROUNDS=
if [[ -z ${SYSINFO_SDC_Version} ]]; then
    ENABLE_6x_WORKAROUNDS="true"
fi

fatal()
{
    echo "Error: $*" >&4
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

function check_ntp
{
    # disable pipefail so we can catch our own errors
    set +o pipefail

    if [[ -n ${MOCKCN} ]]; then
        echo "Not checking NTP in mock CN."
        return;
    fi

    if [[ -z ${TEMP_CONFIGS} && -f /mnt/usbkey/config ]]; then
        # headnode
        TEMP_CONFIGS=/mnt/usbkey
    fi

    if [[ -f ${TEMP_CONFIGS}/node.config ]]; then
        servers=$(cat ${TEMP_CONFIGS}/node.config | grep "^ntp_hosts=" \
            | cut -d'=' -f2- | tr ',' ' ')
        # strip off quoting
        eval servers="$servers"
    fi

    if [[ -z ${servers} ]]; then
        force_dns=
        if [[ $(wc -l /etc/resolv.conf | awk '{ print $1 }') -eq 0 ]]; then
            force_dns="@8.8.8.8"
        fi
        # No NTP hosts set, use some from pool.ntp.org
        servers=$(dig ${force_dns} pool.ntp.org +short | grep "^[0-9]" | xargs)
    fi

    # If we still don't have servers, we're stuck
    if [[ -z ${servers} ]]; then
        fatal "Cannot find any servers to sync with using NTP."
    fi

    # NTP needs to be off and we don't bother turning it back on because we're
    # going to reboot when everything is ok.
    /usr/sbin/svcadm disable svc:/network/ntp:default

    # Poll on headnode ntp availability.

    ntp_wait_duration=600
    ntp_wait_seconds=0
    ntp_wait_interval=10

    set +o errexit
    while true; do
        output=$(ntpdate -b ${servers} 2>&1)
        if [[ $? -eq 0 && -n ${output} ]]; then
            break;
        fi

        # Got an undesireable output/code, run again with debug enabled.
        ntpdate -d ${servers}

        sleep $ntp_wait_interval
        ntp_wait_seconds=$((ntp_wait_seconds + ntp_wait_interval))

        if [[ $ntp_wait_seconds -gt $ntp_wait_duration ]]; then
            fatal "Unable to set system clock: '${output}'"
        fi
    done
    set -o errexit

    # check absolute value of integer portion of offset is reasonable.
    offset=$(ntpdate -q ${servers} | grep "offset .* sec" | \
        sed -e "s/^.*offset //" | cut -d' ' -f1 | tr -d '-' | cut -d'.' -f1)

    if [[ -z ${offset} ]]; then
        fatal "Unable to set system clock, fix NTP settings and try again."
    elif [[ ${offset} -gt 10 ]]; then
        fatal "System clock is off by ${offset} seconds, fix NTP settings" \
            "and try again."
    fi

    echo "Clock OK"

    # reenable pipefail since it was enabled to start with
    set -o pipefail
}

function boot_setup
{
    local console=

    set +o pipefail
    console=$(bootparams | grep ^console= | cut -d= -f2)
    set -o pipefail

    [[ -z "${console}" ]] && console=text

    if [[ ! -f /mnt/usbkey/boot/grub/menu.lst.tmpl ]]; then
        fatal "No GRUB menu found."
    else
        sed -e "s/^default.*/default 1/" \
            -e "s/^variable os_console.*/variable os_console ${console}/" \
            < /mnt/usbkey/boot/grub/menu.lst.tmpl \
            > /tmp/menu.lst.tmpl
        mv -f /tmp/menu.lst.tmpl /mnt/usbkey/boot/grub/menu.lst.tmpl
    fi

    if [[ -f /mnt/usbkey/boot/grub/menu.lst ]]; then
        sed -e "s/^default.*/default 1/" \
            -e "s/^variable os_console.*/variable os_console ${console}/" \
            < /mnt/usbkey/boot/grub/menu.lst \
            > /tmp/menu.lst
        mv -f /tmp/menu.lst /mnt/usbkey/boot/grub/menu.lst
    fi
}

SETUP_FILE=/var/lib/setup.json
if [[ -n ${MOCKCN} ]]; then
    SETUP_FILE="/mockcn/${MOCKCN_SERVER_UUID}/setup.json"
fi

function create_setup_file
{
    TYPE=$1

    # Skip this on 6.x
    [[ -n ${ENABLE_6x_WORKAROUNDS} ]] && return 0

    if [[ ! -e "$SETUP_FILE" ]]; then
        echo "{ \"node_type\": \"$TYPE\", " \
            '"start_time":' \
            "\"$(date "+%Y-%m-%dT%H:%M:%SZ")\", " \
            '"current_state": "", ' \
            '"seen_states": [], ' \
            '"complete": false }' \
            > $SETUP_FILE
        chmod 400 $SETUP_FILE
    fi
}

function update_setup_state
{
    STATE=$1

    # Skip this on 6.x
    [[ -n ${ENABLE_6x_WORKAROUNDS} ]] && return 0

    chmod 600 $SETUP_FILE
    cat "$SETUP_FILE" | json -e \
        "this.current_state = '$STATE';
         this.last_updated = new Date().toISOString();
         this.seen_states.push('$STATE');" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
}

function check_disk_space
{
    local pool_json="$1"
    local RAM_MiB=${SYSINFO_MiB_of_Memory}
    local space=$(/usr/bin/json capacity < ${pool_json})
    local Disk_MiB=$(( $space / 1024 / 1024 ))
    local msg

    msg='Cannot setup: system has %dG memory but %dG disk (>= %dG expected)'

    Min_Disk_MiB=$(( $RAM_MiB * $MIN_DISK_TO_RAM ))

    if [[ ${Disk_MiB} -lt ${Min_Disk_MiB} ]]; then
        local RAM_GiB=$(( $RAM_MiB / 1024 ))
        local Disk_GiB=$(( $Disk_MiB / 1024 ))
        local Min_Disk_GiB=$(( $Min_Disk_MiB / 1024 ))

        msg=$(printf "${msg}" $RAM_GiB $Disk_GiB $Min_Disk_GiB)
        fatal "${msg}"
    fi
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

    if [[ -n ${MOCKCN} ]]; then
        # setup initial usage
        json -e "this.usage = $(($RANDOM * $RANDOM))" \
            < ${POOL_JSON} > ${POOL_JSON}.new \
            && mv ${POOL_JSON}.new ${POOL_JSON}
        echo "Not checking NTP in mock CN."
        return;
    fi

    if ! /usr/sbin/zpool list -H -o name $SYS_ZPOOL; then
        printf "%-56s" "creating pool: $SYS_ZPOOL" >&4
        if ! /usr/bin/mkzpool ${SYS_ZPOOL} ${POOL_JSON}; then
            printf "%6s\n" "failed" >&4
            fatal "failed to create pool"
        fi
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
    zfs create -V ${dumpsize}mb -o checksum=noparity ${SYS_ZPOOL}/dump || \
        fatal "failed to create the dump zvol"
}

#
# Setup the persistent datasets on the zpool.
#
setup_datasets()
{
    datasets=$(zfs list -H -o name | xargs)

    if [[ -n ${MOCKCN} ]]; then
        echo "Not setting up datasets in mock CN."
        return;
    fi

    if ! echo $datasets | grep dump > /dev/null; then
        printf "%-56s" "adding volume: dump" >&4
        create_dump
        printf "%4s\n" "done" >&4
    fi

    if ! echo $datasets | grep ${CONFDS} > /dev/null; then
        printf "%-56s" "adding volume: config" >&4
        zfs create ${CONFDS} || fatal "failed to create the config dataset"
        chmod 755 /${CONFDS}
        cp -p /etc/zones/* /${CONFDS}
        zfs set mountpoint=legacy ${CONFDS}
        printf "%4s\n" "done" >&4
    fi

    if ! echo $datasets | grep ${USBKEYDS} > /dev/null; then
        if is_headnode; then
            printf "%-56s" "adding volume: usbkey" >&4
            zfs create -o mountpoint=legacy ${USBKEYDS} || \
                fatal "failed to create the usbkey dataset"
            printf "%4s\n" "done" >&4
        fi
    fi

    if ! echo $datasets | grep ${COREDS} > /dev/null; then
        printf "%-56s" "adding volume: cores" >&4
        if [[ -z ${ENABLE_6x_WORKAROUNDS} ]]; then
            zfs create -o compression=lz4 -o mountpoint=none ${COREDS} || \
                fatal "failed to create the cores dataset"
            zfs create -o quota=10g -o mountpoint=/${SYS_ZPOOL}/global/cores \
                ${COREDS}/global || \
                fatal "failed to create the global zone cores dataset"
        else
            zfs create -o quota=10g -o mountpoint=/${SYS_ZPOOL}/global/cores \
                -o compression=gzip ${COREDS} || \
                fatal "failed to create the cores dataset"
        fi
        printf "%4s\n" "done" >&4

    fi

    if ! echo $datasets | grep ${OPTDS} > /dev/null; then
        printf "%-56s" "adding volume: opt" >&4
        zfs create -o mountpoint=legacy ${OPTDS} || \
            fatal "failed to create the opt dataset"
        printf "%4s\n" "done" >&4
    fi

    if ! echo $datasets | grep ${VARDS} > /dev/null; then
        printf "%-56s" "adding volume: var" >&4
        zfs create ${VARDS} || fatal "failed to create the var dataset"
        chmod 755 /${VARDS}
        cd /var

        # since we created /var, we setup so that we keep a copy of the joysetup log
        # as log messages written after this will otherwise not be logged due to
        # the cpio moving them to the new /var
        mkdir -p /var/log
        trap "cp /tmp/joysetup.$$ /var/log/joysetup.log" EXIT

        if ( ! find . -print | TMPDIR=/tmp cpio -pdm /${VARDS} ); then
            fatal "failed to initialize the var directory"
        fi

        zfs set mountpoint=legacy ${VARDS} || \
            fatal "failed to set the mountpoint for ${VARDS}"

        zfs set atime=on ${VARDS} || \
            fatal "failed to set atime=on for ${VARDS}"

        printf "%4s\n" "done" >&4
    fi
}

create_swap()
{
    if [[ -n ${MOCKCN} ]]; then
        echo "Not setting up swap on mock CN."
        return;
    fi

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
        printf "%-56s" "adding volume: swap" >&4

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

#
# Print information about each pool imported on this system, either because
# setup has just created this pool, or if the pool was just imported.
#
output_zpool_info()
{
    if [[ -n ${MOCKCN} ]]; then
        pool="zones"
        # XXX should generate one when we create the pool
        guid="14134180013048896962"
        used="$(json usage < ${POOL_JSON})"
        total="$(json capacity < ${POOL_JSON})"
        available=$((${total} - ${used}))
        health="ONLINE"
        mountpoint="/zones"
        printf "${pool}\t${guid}\t${total}\t${available}\t${health}\t${mountpoint}\n"
        return;
    fi

    for pool in $(zpool list -H -o name); do
        guid=$(zpool list -H -o guid ${pool})
        used=$(zfs get -Hp -o value used ${pool})
        available=$(zfs get -Hp -o value available ${pool})
        health=$(zpool get health ${pool} | grep -v NAME | awk '{print $3}')
        mountpoint=$(zfs get -Hp -o value mountpoint ${pool})

        total=$((${used} + ${available}))

        printf "${pool}\t${guid}\t${total}\t${available}\t${health}\t${mountpoint}\n"
    done
}

# Loads config files for the node. These are the config values from the headnode
# plus authorized keys and anything else we want
install_configs()
{
    SMARTDC=/opt/smartdc/config

    # On standalone machines we don't get config in /var/tmp
    if [[ -n $(/usr/bin/bootparams | grep "^standalone=true") ]]; then
        return 0
    fi

    if ! is_headnode; then
        printf "%-56s" "Compute node, installing config files... " >&4
        if [[ ! -d $TEMP_CONFIGS ]]; then
            fatal "config files not present in $TEMP_CONFIGS"
        fi

        if [[ -n ${MOCKCN} ]]; then
            mv $TEMP_CONFIGS /mockcn/${MOCKCN_SERVER_UUID}/config
            printf "%4s\n" "done" >&4
            return
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

setup_filesystems()
{
    if [[ -n ${MOCKCN} ]]; then
        echo "Not setting up filesystems on mock CN."
        return;
    fi

    cd /
    svcadm disable -s filesystem/smartdc
    svcadm enable -s filesystem/smartdc
    svcadm disable -s filesystem/minimal
    svcadm enable -s filesystem/minimal
    if ! is_headnode; then
        # Only restart smartdc/config on CN, on HN we're rebooting.
        svcadm disable -s smartdc/config
        svcadm enable -s smartdc/config
    fi
}

is_headnode()
{
    if [[ -z "$__headnode_known" ]]; then
        __headnode_bp="$(/usr/bin/bootparams | grep "^headnode=true")"
        __headnode_known=true
    fi
    if [[ -z "$__headnode_bp" ]]; then
        return 1    # "failure" == false == 1
    else
        return 0    # "success" == true == 0
    fi
}

if [[ "$(zpool list)" == "no pools available" ]] \
    || [[ -n ${MOCKCN} && ! -f ${SETUP_FILE} ]]; then

    if ! is_headnode; then
        # On headnodes we assume prompt-config already worked out a
        # valid ntp config, on compute nodes we make sure that it is
        # set before setup starts.
        check_ntp
    fi

    POOL_FILE=/tmp/pool.json
    if [[ -n ${MOCKCN} ]]; then
        POOL_FILE=/mockcn/${MOCKCN_SERVER_UUID}/pool.json
    fi

    if ! /usr/bin/disklayout "${arg_disklayout}" > ${POOL_FILE}; then
        fatal "disk layout failed"
    fi

    check_disk_space ${POOL_FILE}
    create_zpool zones ${POOL_FILE}

    if is_headnode; then
        boot_setup
    fi

    if is_headnode; then
        create_setup_file headnode
    else
        create_setup_file computenode
    fi

    update_setup_state "zpool_created"

    setup_datasets
    update_setup_state "datasets_setup"

    install_configs
    update_setup_state "configs_installed"

    create_swap
    update_setup_state "swap_created"

    output_zpool_info

    setup_filesystems
    update_setup_state "filesystems_setup"

    if [[ -n ${MOCKCN} ]]; then
        # nothing below here needs to run for mock CN
        update_setup_state "imgadm_setup"
        exit 0
    fi

    if ! is_headnode; then
        # On a CN we're not rebooting, so we want the following
        # reloaded.  Restarting zones causes /zones/manifests/ to be
        # populated.
        svcadm restart svc:/system/zones:default
    fi

    # Restarting network/physical causes /etc/resolv.conf to be written out.
    # We do disable/enable so we can use -s.  We need this to finish here so
    # that resolv.conf is updated, since node (imgadm) needs resolv.conf to
    # be populated before it starts, as it does not notice changes.  We
    # also restart routing-setup here to pick up defaultrouter, also
    # written by network/physical.
    svcadm disable -s svc:/network/physical:default
    # in 6.x disable doesn't really disable everything, we'll fix that up here
    if [[ -n ${ENABLE_6x_WORKAROUNDS} ]]; then
        set +o errexit
        set +o pipefail
        for iface in $(ifconfig -a | grep ^[a-z] | cut -d':' -f1 | grep -v "^lo" | sort | uniq); do
            ifconfig ${iface} down
            ifconfig ${iface} unplumb
            dladm remove-bridge -l ${iface} vmwarebr
        done
        dladm delete-bridge vmwarebr
        set -o errexit
        set -o pipefail
    fi
    svcadm enable -s svc:/network/physical:default
    svcadm disable -s svc:/network/routing-setup:default
    svcadm enable -s svc:/network/routing-setup:default

    echo $(cat /etc/resolv.conf)

    if [[ -z ${ENABLE_6x_WORKAROUNDS} ]]; then
        # imgadm setup to use the IMGAPI in this DC.
        if [[ ! -f /var/imgadm/imgadm.conf ]]; then
            mkdir -p /var/imgadm
            echo '{}' > /var/imgadm/imgadm.conf
        fi
        if [[ -z "$(json -f /var/imgadm/imgadm.conf sources)" ]]; then
            imgadm sources -f -a http://$CONFIG_imgapi_domain
            imgadm sources -f -d https://images.joyent.com  # remove the default
        fi

        update_setup_state "imgadm_setup"
    fi

    # We're the headnode

else
    output_zpool_info
fi

exit 0
