#!/usr/bin/bash
#
# Copyright (c) 2010,2011 Joyent Inc., All rights reserved.
#
# Exit codes:
#
# 0 - success
# 1 - error
# 2 - rebooting (don't bother doing anything)
#

#
# We set errexit (a.k.a. "set -e") to force an exit on error conditions, and
# pipefail to force any failures in a pipeline to force overall failure.  We
# also set xtrace to aid in debugging.
#
set -o errexit
set -o pipefail
set -o xtrace

CONSOLE_FD=4 ; export CONSOLE_FD
exec 4>>/dev/console

function fatal
{
    echo "head-node configuration: fatal error: $*" >&${CONSOLE_FD}
    echo "head-node configuration: fatal error: $*"
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

function find_platform_id
{
    platform_id=

    for line in $(/smartdc/bin/sdc-mapi /admin/platform_images \
        | /usr/xpg4/bin/grep -e '"id"' -e '"name"' \
        | tr -d ' ,"' \
        | tr ':' '=' \
        | xargs -L 2 \
        | tr ' ' ',' \
        | grep "HVM-"); do

        # we should have something like id=1,name=xyz
        # set these as variables id and name
        eval ${line%,*}
        eval ${line#*,}

        if [[ -n ${id} && -n ${name} ]]; then
            ary[${id}]=${name}
        fi
    done

    latest_hvm=$(echo ${ary[@]} | tr ' ' '\n' | sort | tail -1)

    i=0
    while [[ -z ${platform_id} ]]; do
        if [[ ${latest_hvm} == ${ary[${i}]} ]]; then
            platform_id=${i};
        fi
        i=$((${i} + 1))
    done
}

function create_hvm_server_role
{
    find_platform_id
    if [[ -n ${platform_id} ]]; then
        /smartdc/bin/sdc-mapi /admin/server_roles -X POST -F name=hvm -F platform_image_id=${platform_id}
    fi
}

function install_hvm_platforms
{
    platforms=$(find ${USB_COPY}/data -name "platform-hvm-*.tgz")
    if [[ -n ${platforms} ]]; then
        for f in ${platforms}; do
            ${USB_COPY}/scripts/install-platform.sh file://${f}
            rm -f ${f}
        done
        create_hvm_server_role
    fi
}

function install_config_file
{
    option=$1
    target=$2

    # pull out those config options we want to keep
    filename=$(
        . ${USB_COPY}/config
	. ${USB_COPY}/config.inc/generic
        eval echo "\${${option}}"
    )

    if [[ -n ${filename} ]] && [[ -f "${USB_COPY}/config.inc/${filename}" ]]; then
        cp "${USB_COPY}/config.inc/${filename}" "${target}"
    fi
}

trap 'errexit $?' EXIT

DEBUG="true"

USB_PATH=/mnt/`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/smartdc:default`
USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/smartdc:default`

# Load config variables with CONFIG_ prefix
. /lib/sdc/config.sh
load_sdc_config

# Now the infrastructure zones
# check if we've imported a zpool
POOLS=`zpool list`

if [[ ${POOLS} == "no pools available" ]]; then

    ${USB_PATH}/scripts/joysetup.sh || exit 1

    ds_uuid=$(cat ${USB_PATH}/datasets/smartos.uuid)
    ds_file=$(cat ${USB_PATH}/datasets/smartos.filename)

    if [[ -z ${ds_uuid} || -z ${ds_file} \
        || ! -f ${USB_PATH}/datasets/${ds_file} ]]; then

        fatal "FATAL: unable to find 'smartos' dataset."
    fi

    printf "%-56s" "Importing zone template dataset... " >&${CONSOLE_FD}
    bzcat ${USB_PATH}/datasets/${ds_file} \
        | zfs recv zones/${ds_uuid} \
        || fatal "unable to import ${template}"

    printf "%4s\n" "done" >&${CONSOLE_FD}

    reboot
    exit 2
fi

if ( zoneadm list -i | grep -v "^global$" ); then
    ZONES=`zoneadm list -i | grep -v "^global$"`
else
    ZONES=
fi

USBZONES=`ls ${USB_COPY}/zones`
ALLZONES=`for x in ${ZONES} ${USBZONES}; do echo ${x}; done | sort -r | uniq | xargs`
CREATEDZONES=

# Create link for latest platform
create_latest_link

for zone in $ALLZONES; do
    if [[ -z $(echo "${ZONES}" | grep ${zone}) ]]; then

        # This is to move us to the next line past the login: prompt
        [[ -z "${CREATEDZONES}" ]] && echo "" >&${CONSOLE_FD}

        skip=false
        if [ "${zone}" == "capi" ] ; then
            if ! ${CONFIG_capi_is_local} ; then
                skip=true
            fi
        fi

        if ! ${skip} ; then
            ${USB_COPY}/scripts/create-zone.sh ${zone}
            CREATEDZONES="${CREATEDZONES} ${zone}"
        fi

    fi
done

if [ -n "${CREATEDZONES}" ]; then
    # Wait for all the zones here instead of using create-zone -w
    # So that we can spin them all up in parallel and cook our laps
    for zone in ${CREATEDZONES}; do
        if [ -e /zones/${zone}/root/root/zoneinit ]; then
        	  msg="${zone}: waiting for zoneinit"
            loops=0
            while [ -e /zones/${zone}/root/root/zoneinit ]; do
                printf "%-56s%s\r" "${msg}" "-"  >&${CONSOLE_FD} ; sleep 0.05
                printf "%-56s%s\r" "${msg}" "\\" >&${CONSOLE_FD} ; sleep 0.05
                printf "%-56s%s\r" "${msg}" "|"  >&${CONSOLE_FD} ; sleep 0.05
                printf "%-56s%s\r" "${msg}" "/"  >&${CONSOLE_FD} ; sleep 0.05
      
                # counter goes up every 0.2 seconds
                # wait 10 minutes
                loops=$((${loops} + 1))
                [ ${loops} -ge 2999 ] && break
            done
            if [ ${loops} -ge 2999 ]; then
                printf "%-56s%8s\n" "${msg}" "timeout!"  >&${CONSOLE_FD}
                ls -l /zones/${zone}/root/root >&${CONSOLE_FD}
            else
                printf "%-56s%4s\n" "${msg}" "done"  >&${CONSOLE_FD}
                # remove the pkgsrc dir now that zoneinit is done
                if [[ -d /zones/${zone}/root/pkgsrc ]]; then
                    rm -rf /zones/${zone}/root/pkgsrc
                fi
            fi
        fi
    done

    # We do this here because agents assume rabbitmq is up and by this point it
    # should be.
    if [[ ( $CONFIG_install_agents != "false"   && \
            $CONFIG_install_agents != "0"     ) && \
          ! -e "/opt/smartdc/agents/bin/atropos-agent" ]]; then
        which_agents=$(ls -1 ${USB_PATH}/ur-scripts/agents-*.sh \
            | grep -v -- '-hvm-' | tail -n1)
        if [[ -n ${which_agents} ]]; then
            printf "%-56s" "Installing $(basename ${which_agents})... " >&${CONSOLE_FD}
            (cd /var/tmp ; bash ${which_agents})
            printf "%4s\n" "done" >&${CONSOLE_FD}
        else
            fatal "No agents-*.sh found!"
        fi
    fi

    # Check that all of the zone's svcs are up before we end.
    # The svc installing the zones is still running since we haven't exited
    # yet, so the svc count should be 1 for us to end successfully.
    # If they're not up after 4 minutes, report a possible issue.
    printf "%-56s\n" "Waiting for zones to finish starting up..." >&${CONSOLE_FD}
    i=0
    while [ $i -lt 16 ]; do
        nstarting=`svcs -Zx 2>&1 | grep -c "State:"`
        if [ $nstarting -lt 2 ]; then
                break
        fi
        sleep 15
        i=`expr $i + 1`
    done
    echo "" >&${CONSOLE_FD}

    if [ $nstarting -gt 1 ]; then
        echo "Warning: services in the following zones are still not running:" \
            >&${CONSOLE_FD}
        svcs -Zx | nawk '{if ($1 == "Zone:") print $2}' | sort -u \
            >&${CONSOLE_FD}
    fi

    # Install any HVM platforms that are sitting around, do this here since MAPI is now up.
    install_hvm_platforms
   
    # Run a post-install script. This feature is not formally supported in SDC
    if [ -f ${USB_COPY}/scripts/post-install.sh ] ; then
    	printf "%-56s\n" "Executing post-install script..." >&${CONSOLE_FD}
    	bash ${USB_COPY}/scripts/post-install.sh
    fi

    # clear the screen
    echo "[H[J" >&${CONSOLE_FD}
    
    echo "==> Setup complete.  Press [enter] to get login prompt." \
        >&${CONSOLE_FD}
    echo "" >&${CONSOLE_FD}
fi

exit 0
