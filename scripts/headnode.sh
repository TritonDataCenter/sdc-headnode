#!/usr/bin/bash
#
# Copyright (c) 2012, Joyent, Inc. All rights reserved.
#
# Exit codes:
#
# 0 - success
# 1 - error
# 2 - rebooting (don't bother doing anything)
#

unset LD_LIBRARY_PATH
PATH=/usr/bin:/usr/sbin:/smartdc/bin
export PATH

#
# We set errexit (a.k.a. "set -e") to force an exit on error conditions, and
# pipefail to force any failures in a pipeline to force overall failure.  We
# also set xtrace to aid in debugging.
#
set -o errexit
set -o pipefail
# this is set below
#set -o xtrace

CONSOLE_FD=4 ; export CONSOLE_FD

function fatal
{
    printf "%-80s\r" " " >&${CONSOLE_FD}
    echo "headnode configuration: fatal error: $*" >&${CONSOLE_FD}
    echo "headnode configuration: fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0
    fatal "error exit status $1"
}

function create_latest_link
{
    rm -f ${USB_COPY}/os/latest
    latest=$(cd ${USB_COPY}/os && ls -d * | tail -1)
    (cd ${USB_COPY}/os && ln -s ${latest} latest)
}

function cr_once
{
    if [[ -z ${did_cr_once} ]]; then
        # This is to move us to the beginning of the line with the login: prompt
        printf "\r" >&${CONSOLE_FD}
        did_cr_once=1
    fi
}

#
# MAPI needs some extra data files, all MAPI specific stuff should be here.
#
function copy_special_mapi_files
{
    dir=${USB_COPY}/extra/mapi

    sysinfo > ${dir}/headnode-sysinfo.json
    mkdir -p ${dir}/datasets
    cp ${USB_COPY}/datasets/*.dsmanifest ${dir}/datasets/
    rm -f ${dir}/joysetup.sh
    ln ${USB_COPY}/scripts/joysetup.sh ${dir}/joysetup.sh
    mkdir -p ${dir}/agents
    rm -f ${dir}/agents/*.sh
    ln ${USB_COPY}/ur-scripts/agents-*.sh ${dir}/agents/
    mkdir -p ${dir}/config.inc
    rm -rf ${dir}/config.inc/*
    for file in \
        $(find ${USB_COPY}/config.inc/ -maxdepth 1 -type f -not -name ".*"); do
        ln ${file} ${dir}/config.inc/
    done
}

# Create packages for internal-use
function setup_sdc_pkgs
{
    # Wait for mapi to be ready to load packages
    set +o errexit
    cnt=0
    while [ $cnt -lt 10 ]
    do
	sleep 30
	curl -f -s \
            -u ${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw} \
	    http://$CONFIG_mapi_admin_ip/packages >/dev/null 2>&1
	[ $? == 0 ] && break
	let cnt=$cnt+1
    done
    set -o errexit
    [ $cnt -eq 10 ] && \
        echo "Warning: MAPI still not ready to load packages" >&${CONSOLE_FD}

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
            -d owner_uuid=$CONFIG_ufds_admin_uuid
    done
}

trap 'errexit $?' EXIT

#
# On initial install, do the extra logging, but for restore, we want cleaner
# output.
#
restore=0
if [ $# == 0 ]; then
    DEBUG="true"
    exec 4>>/dev/console
    set -o xtrace
else
    exec 4>>/dev/stdout
    restore=1
    export PS4='${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    export BASH_XTRACEFD=2
    set -o xtrace
fi

USB_PATH=/mnt/`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/smartdc:default`
USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/smartdc:default`

# Load config variables with CONFIG_ prefix
. /lib/sdc/config.sh
load_sdc_config

# Now the infrastructure zones
# check if we've imported a zpool
POOLS=`zpool list`

if [[ ${POOLS} == "no pools available" ]]; then

    cr_once

    ${USB_PATH}/scripts/joysetup.sh || exit 1

    ds_uuid=$(cat ${USB_PATH}/datasets/smartos.uuid)
    ds_file=$(cat ${USB_PATH}/datasets/smartos.filename)

    if [[ -z ${ds_uuid} || -z ${ds_file} \
        || ! -f ${USB_PATH}/datasets/${ds_file} ]]; then

        fatal "FATAL: unable to find 'smartos' dataset."
    fi

    printf "%-56s" "importing SMI: smartos" >&${CONSOLE_FD}
    bzcat ${USB_PATH}/datasets/${ds_file} \
        | zfs recv zones/${ds_uuid} \
        || fatal "unable to import ${template}"

    printf "%4s\n" "done" >&${CONSOLE_FD}

    reboot
    exit 2
fi

if [[ ${CONFIG_stop_before_setup} == "true" || \
    ${CONFIG_stop_before_setup} == "0" ]]; then

    # This option exists for development and testing, it allows the setup to be
    # stopped after the zpool is created but before any of the agents or
    # headnode zones are setup.
    exit 0
fi

# Setup the pkgsrc directory for the core zones to pull files from.
if [[ ! -d ${USB_COPY}/extra/pkgsrc ]]; then
    mkdir -p ${USB_COPY}/extra/pkgsrc
    for pkgsrcfile in $(ls -1 ${USB_COPY}/data/pkgsrc_*); do
        rm -f ${USB_COPY}/extra/pkgsrc/$(basename ${pkgsrcfile})
        ln ${pkgsrcfile} ${USB_COPY}/extra/pkgsrc/$(basename ${pkgsrcfile})
    done
fi

# For dev/debugging, you can set the SKIP_AGENTS environment variable.
if [[ -z ${SKIP_AGENTS} && ! -x "/opt/smartdc/agents/bin/apm" ]]; then
    cr_once
    # Install the agents here so initial zones have access to metadata.
    which_agents=$(ls -1 ${USB_PATH}/ur-scripts/agents-*.sh \
        | grep -v -- '-hvm-' | tail -n1)
    if [[ -n ${which_agents} ]]; then
        if [ $restore == 0 ]; then
            printf "%-58s" "installing $(basename ${which_agents})... " \
                >&${CONSOLE_FD}
            (cd /var/tmp ; bash ${which_agents})
        else
            printf "%-58s" "installing $(basename ${which_agents})... " \
                >&${CONSOLE_FD}
            (cd /var/tmp ; bash ${which_agents} >&4 2>&1)
        fi
        printf "%4s\n" "done" >&${CONSOLE_FD}
    else
        fatal "No agents-*.sh found!"
    fi
fi

if [[ -f /.dcinfo ]]; then
    eval $(cat /.dcinfo)
fi
if [[ -z ${SDC_DATACENTER_HEADNODE_ID} ]]; then
    SDC_DATACENTER_HEADNODE_ID=0
fi
export SDC_DATACENTER_NAME SDC_DATACENTER_HEADNODE_ID


# headnode.sh normally does the initial setup of the headnode when it first
# boots.  This creates the core zones, installs agents, etc.  However, when
# we are booting with the standby option, if there is a backup file on the
# USB key, then we want to create plus restore things in this case.
#
# If we're setting up a standby headnode, we might have rebooted from the
# joysetup in the block above.  In that case, joysetup left a cookie named
# /zones/.standby.  So we have two conditions to setup a standby headnode,
# otherwise we setup normally.
#
# XXX what if boot standby and things are already setup?  Delete first?
#
# We want to be careful here since, sdc-restore -F will also run this
# headnode.sh script (with the restore parameter) and we want that to work
# even if the system was initially booted as a standby.
standby=0
if [ $restore == 0 ]; then
    if /bin/bootparams | grep "^standby=true" >/dev/null 2>&1; then
        standby=1
    elif [ -e /zones/.standby ]; then
        standby=1
    fi
fi

if [ $standby == 1 ]; then
    # See if there is a backup on the USB key
    [ -d ${USB_COPY}/standby ] && \
        bufile=${USB_COPY}/standby/`ls -t ${USB_COPY}/standby 2>/dev/null | head -1`
fi
[[ $standby == 1 && -z "$bufile" ]] && skip_zones=true

CREATEDZONES=
CREATEDUUIDS=

# Create link for latest platform
create_latest_link

# HOW THE CORE ZONE PROCESS WORKS:
#
# In the /usbkey/zones/<zone> directory you can have any of:
#
# configure.sh backup restore setup user-script
#
# When creating we also hard link these files to /usbkey/extra if they exist.
#
# When the assets zone is created /usbkey/extra is mounted in as /assets/extra
# and is exposed from there over HTTP.  The user-script is passed in as metadata
# and run through the mdata service in the zone after reboot from zoneinit. The
# user-script should just download the files above (to /opt/smartdc/bin) and run
# setup.
#
# Most of the time these zones won't need their own user-script and can just use
# the default one in /usbkey/default/user-script.common which will be applied by
# build-payload.js if a zone-specific one is not found.
#
# The setup script usually does some initial setup and then runs through the
# configuration.


# Install the core headnode zones

function create_zone {
    zone=$1
    new_uuid=$(uuid -v4)

    # Do a lookup here to ensure zone with this role doesn't exist
    existing_uuid=$(vmadm lookup tags.smartdc_role=${zone})
    if [[ -n ${existing_uuid} ]]; then
        echo "Skipping creation of ${zone} as ${existing_uuid} already has" \
            "that role."
        return 0
    fi

    # If OLD_ZONES was passed in the environment, use the UUID there, this
    # is for sdc-restore.
    existing_uuid=
    if [[ -n ${OLD_ZONES} ]]; then
        for z in ${OLD_ZONES}; do
            uuid=${z%%,*}
            tag=${z##*,}
            if [[ ${tag} == ${zone} && -n ${uuid} ]]; then
                new_uuid=${uuid}
                existing_uuid="(${new_uuid}) "
            fi
        done
    fi

    # This just moves us to the beginning of the line (once)
    cr_once

    # If zone has specified dataset_uuid, we need to ensure that's imported.
    if [[ -f ${USB_COPY}/zones/${zone}/create.json ]]; then
        extra_dataset=$(cat ${USB_COPY}/zones/${zone}/create.json 2>/dev/null \
            | json dataset_uuid)
        if [[ -n ${extra_dataset} && ! -d /zones/${extra_dataset} ]]; then
            found=0
            for file in $(ls ${USB_COPY}/datasets/*.dsmanifest); do
                res=$(cat ${file} | json -a uuid files.0.path | tr ' ' ',')
                ds_uuid=$(echo ${res} | cut -d',' -f1)
                ds_file=$(echo ${res} | cut -d',' -f2)
                if [[ ${ds_uuid} == ${extra_dataset} ]]; then
                    printf "%-58s" "importing SMI: ${zone}" \
                        >&${CONSOLE_FD}
                    bzcat ${USB_PATH}/datasets/${ds_file} \
                        | zfs recv zones/${ds_uuid} \
                        || fatal "unable to import ${template}"
                    found=1
                    echo "done" >&${CONSOLE_FD}
                fi
            done
            if [[ ${found} == 0 ]]; then
                fatal "unable to find dataset ${extra_dataset} for ${zone}"
            fi
        fi
    fi

    if [[ ${restore} == 0 ]]; then
        printf "%-58s" "creating zone ${existing_uuid}${zone}... " \
            >&${CONSOLE_FD}
    else
        # alternate format for sdc-restore
        printf "%s" "creating zone ${existing_uuid}${zone}... " \
            >&${CONSOLE_FD}
    fi
    dir=${USB_COPY}/extra/${zone}
    mkdir -p ${dir}
    rm -f ${dir}/pkgsrc
    ln ${USB_COPY}/zones/${zone}/pkgsrc ${dir}/pkgsrc
    if [[ -f ${USB_COPY}/zones/${zone}/fs.tar.bz2 ]]; then
        rm -f ${dir}/fs.tar.bz2
        ln ${USB_COPY}/zones/${zone}/fs.tar.bz2 ${dir}/fs.tar.bz2
    fi
    for file in configure backup restore setup; do
        if [[ -f ${USB_COPY}/zones/${zone}/${file} ]]; then
            rm -f ${dir}/${file}
            ln ${USB_COPY}/zones/${zone}/${file} ${dir}/${file}
        fi
    done
    if [[ -f ${USB_COPY}/default/setup.common ]]; then
        # extra include file for core zones.
        rm -f ${dir}/setup.common
        ln ${USB_COPY}/default/setup.common ${dir}/setup.common
    fi
    if [[ -f ${USB_COPY}/rc/zone.root.bashrc ]]; then
        rm -f ${dir}/bashrc
        ln ${USB_COPY}/rc/zone.root.bashrc ${dir}/bashrc
    fi

    if [[ -f ${USB_COPY}/zones/${zone}/zoneconfig ]]; then
        # This allows zoneconfig to use variables that exist in the <USB>/config
        # file, by putting them in the environment then putting the zoneconfig
        # in the environment, then printing all the variables from the file.  It
        # is done in a subshell to avoid further namespace polution.
        (
            . ${USB_COPY}/config
            . ${USB_COPY}/config.inc/generic
            . ${USB_COPY}/zones/${zone}/zoneconfig
            for var in $(cat ${USB_COPY}/zones/${zone}/zoneconfig \
                | grep -v "^ *#" | grep "=" | cut -d'=' -f1); do

                echo "${var}='${!var}'"
            done
        ) > ${dir}/zoneconfig
    fi

    # MAPI needs some files for CNs that we don't need for other zones.
    if [[ ${zone} == "mapi" ]]; then
        copy_special_mapi_files
    fi

    NODE_PATH="/usr/node_modules:${NODE_PATH}" \
        ${USB_COPY}/scripts/build-payload.js ${zone} ${new_uuid} | vmadm create
    echo "done" >&${CONSOLE_FD}

    CREATEDZONES="${CREATEDZONES} ${zone}"
    CREATEDUUIDS="${CREATEDUUIDS} ${new_uuid}"

    return 0
}

# This takes a list of zone uuids and returns a number of those that are missing
# the /var/svc/setup_complete file which normally indicates the zone is setup.
function num_not_setup {
    remain=0

    for uuid in $*; do
        zonepath=$(vmadm get ${uuid} | /usr/bin/json zonepath)
        if [[ ! -f ${zonepath}/root/var/svc/setup_complete ]]; then
            remain=$((${remain} + 1))
        fi
    done

    echo ${remain}
}

if [[ ! ${skip_zones} ]]; then
    # Create assets first since others will download stuff from here.
    export ASSETS_IP=${CONFIG_assets_admin_ip}
    create_zone assets
    create_zone dhcpd
    create_zone rabbitmq
    create_zone mapi
fi

if [ -n "${CREATEDZONES}" ]; then
    # Check that all of the zone's svcs are up before we end.
    # The svc installing the zones is still running since we haven't exited
    # yet, so the svc count should be 1 for us to end successfully.
    # If they're not up after 4 minutes, report a possible issue.
    if [ $restore == 0 ]; then
        msg="Waiting for services to finish starting..."
        printf "%-58s\r" "${msg}"
    else
        # alternate formatting when restoring (sdc-restore)
        msg="waiting for services to finish starting... "
        printf "%s\r" "${msg}"
    fi
    i=0
    while [ $i -lt 48 ]; do
        nstarting=`svcs -Zx 2>&1 | grep -c "State:" || true`
        if [ $nstarting -lt 2 ]; then
                break
        fi
        if [[ -z ${CONFIG_disable_spinning} || ${restore} == 1 ]]; then
            printf "%-58s%s\r" "${msg}" "${nstarting}" >&${CONSOLE_FD}
        fi
        sleep 5
        i=`expr $i + 1`
    done
    if [[ ${restore} == 0 ]]; then
        printf "%-58s%s\n" "${msg}" "done" >&${CONSOLE_FD}
    else
        # alternate formatting when restoring (sdc-restore)
        printf "%s%-20s\n" "${msg}" "done" >&${CONSOLE_FD}
    fi

    if [ $nstarting -gt 1 ]; then
        echo "Warning: services in the following zones are still not running:" \
            >&${CONSOLE_FD}
        svcs -Zx | nawk '{if ($1 == "Zone:") print $2}' | sort -u \
            >&${CONSOLE_FD}
    fi

    # The SMF services should now be up, so we wait for the setup scripts
    # in each of the created zones to be completed (these run in the
    # background for all but assets so may not have finished with the services)
    i=0
    nsettingup=$(num_not_setup ${CREATEDUUIDS})
    while [[ ${nsettingup} -gt 0 && ${i} -lt 48 ]]; do
        if [[ ${restore} == 0 ]]; then
            msg="Waiting for zones to finish setting up..."
        else
            msg="waiting for zones to finish setting up... "
        fi
        if [[ -z ${CONFIG_disable_spinning} || ${restore} == 1 ]]; then
            printf "%-58s%s\r" "${msg}" "${nsettingup}" >&${CONSOLE_FD}
        fi
        i=$((${i} + 1))
        sleep 5
        nsettingup=$(num_not_setup ${CREATEDUUIDS})
    done

    if [[ ${nsettingup} -gt 0 ]]; then
        printf "%-58s%s\n" "${msg}" "failed"  >&${CONSOLE_FD}
        fatal "Warning: some zones did not finish setup, installation has " \
            "failed."
    elif [[ ${restore} == 0 ]]; then
        printf "%-58s%s\n" "${msg}" "done"  >&${CONSOLE_FD}
    else
        # alternate formatting when restoring (sdc-restore)
        printf "%s%-20s\n" "${msg}" "done"  >&${CONSOLE_FD}
    fi

    if [[ ${restore} == 0 && ${standby} == 0 ]]; then
        for i in $CREATEDZONES
        do
            [[ $i == "mapi" && -z ${SKIP_SDC_PKGS} ]] && setup_sdc_pkgs
        done
    fi

    if [ $standby == 1 ]; then
        if [ -n "$bufile" ]; then
             # We have to do the restore in the background since svcs the
             # restore will depend on are blocked waiting for the init svc
             # to complete.
             sdc-restore -S $bufile >&${CONSOLE_FD} 2>&1 &
        fi

        # Cleanup the cookie that joysetup might have left around.
        rm -f /zones/.standby
    fi

    # Run a post-install script. This feature is not formally supported in SDC
    if [ -f ${USB_COPY}/scripts/post-install.sh ]; then
        printf "%-58s" "Executing post-install script..." >&${CONSOLE_FD}
        bash ${USB_COPY}/scripts/post-install.sh
        echo "done" >&${CONSOLE_FD}
    fi

    if [ $restore == 0 ]; then
        # clear the screen
        #echo "[H[J" >&${CONSOLE_FD}

        echo "" >&${CONSOLE_FD}
        if [ $standby == 1 ]; then
            echo "Restoring standby headnode" >&${CONSOLE_FD}
        else
            echo "==> Setup complete.  Press [enter] to get login prompt." \
                >&${CONSOLE_FD}
        fi
        echo "" >&${CONSOLE_FD}
    fi
else
    if [ $restore == 0 ]; then
        if [[ $standby == 1 && -z "$bufile" ]]; then
            # clear the screen
            #echo "[H[J" >&${CONSOLE_FD}

            echo "" >&${CONSOLE_FD}
            echo "==> Use sdc-restore to perform setup.  Press [enter] to get" \
                " login prompt." >&${CONSOLE_FD}
            echo "" >&${CONSOLE_FD}
            # Cleanup the cookie that joysetup might have left around.
            rm -f /zones/.standby
        fi
    fi
fi

if [[ -f ${USB_COPY}/webinfo.tar && ! -d /opt/smartdc/webinfo ]]; then
    ( mkdir -p /opt/smartdc && cd /opt/smartdc  && cat ${USB_COPY}/webinfo.tar \
        | tar -xf - )
fi

( svccfg import /opt/smartdc/webinfo/smf/smartdc-webinfo.xml || /usr/bin/true )

exit 0
