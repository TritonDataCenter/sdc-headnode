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
# set -o xtrace

CONSOLE_FD=4 ; export CONSOLE_FD

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

if [[ ${CONFIG_stop_before_setup} == "true" || \
    ${CONFIG_stop_before_setup} == "0" ]]; then

    # This option exists for development and testing, it allows the setup to be
    # stopped after the zpool is created but before any of the agents or
    # headnode zones are setup.
    exit 0
fi

# Install the agents here so initial zones have access to metadata.
which_agents=$(ls -1 ${USB_PATH}/ur-scripts/agents-*.sh \
    | grep -v -- '-hvm-' | tail -n1)
if [[ -n ${which_agents} ]]; then
    printf "%-56s" "Installing $(basename ${which_agents})... " >&${CONSOLE_FD}
    if [ $restore == 0 ]; then
        (cd /var/tmp ; bash ${which_agents})
    else
        (cd /var/tmp ; bash ${which_agents} >/dev/null 2>&1)
    fi
    printf "%4s\n" "done" >&${CONSOLE_FD}
else
    fatal "No agents-*.sh found!"
fi

if ( zoneadm list -i | grep -v "^global$" ); then
    ZONES=`zoneadm list -i | grep -v "^global$"`
else
    ZONES=
fi

USBZONES="assets dhcpd mapi rabbitmq"
ALLZONES=`for x in ${ZONES} ${USBZONES}; do echo ${x}; done | sort -r | uniq | xargs`

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
    [ -d /usbkey/standby ] && \
        bufile=/usbkey/standby/`ls -t /usbkey/standby 2>/dev/null | head -1`
fi

CREATEDZONES=

# Create link for latest platform
create_latest_link

for zone in $ALLZONES; do
    if [[ -z $(echo "${ZONES}" | grep ${zone}) ]]; then

        # This is to move us to the next line past the login: prompt
        [[ -z "${CREATEDZONES}" ]] && echo "" >&${CONSOLE_FD}

        skip=false
        if [ "${zone}" == "ufds" ] ; then
            if ! ${CONFIG_ufds_is_local} ; then
                skip=true
            fi
        fi

	# If booted for standby headnode but no backup on USB, skip creating
	# the zones at this point.
	[[ $standby == 1 && -z "$bufile" ]] && skip=true

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

    # Check that all of the zone's svcs are up before we end.
    # The svc installing the zones is still running since we haven't exited
    # yet, so the svc count should be 1 for us to end successfully.
    # If they're not up after 4 minutes, report a possible issue.
    printf "%-56s\n" "Waiting for zones to finish starting up..." >&${CONSOLE_FD}
    i=0
    while [ $i -lt 16 ]; do
        nstarting=`svcs -Zx 2>&1 | grep -c "State:" || true`
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
    if [ -f ${USB_COPY}/scripts/post-install.sh ] ; then
    	printf "%-56s\n" "Executing post-install script..." >&${CONSOLE_FD}
    	bash ${USB_COPY}/scripts/post-install.sh
    fi

    if [ $restore == 0 ]; then
	# clear the screen
	echo "[H[J" >&${CONSOLE_FD}

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
	    echo "[H[J" >&${CONSOLE_FD}

	    echo "==> Use sdc-restore to perform setup.  Press [enter] to get login prompt." \
	        >&${CONSOLE_FD}
	    echo "" >&${CONSOLE_FD}
	    # Cleanup the cookie that joysetup might have left around.
            rm -f /zones/.standby
        fi
    fi
fi

if [[ -f /usbkey/webinfo.tar && ! -d /opt/smartdc/webinfo ]]; then
  ( mkdir -p /opt/smartdc && cd /opt/smartdc  && cat /usbkey/webinfo.tar | tar -xf - )
fi

( svccfg import /opt/smartdc/webinfo/smf/smartdc-webinfo.xml || /usr/bin/true )

if [[ -f /.dcinfo ]]; then
    eval $(cat /.dcinfo)
fi

if [[ -z ${SDC_DATACENTER_HEADNODE_ID} ]]; then
    SDC_DATACENTER_HEADNODE_ID=0
fi

for zonename in $USBZONES; do
    zoneuuid=$(/usr/vm/sbin/vmadm lookup zonename=${zonename})
    if [ -n "$zoneuuid" ]; then
        zonealias=$(/usr/vm/sbin/vmadm json ${zoneuuid} | json "alias")
        if [[ -z ${zonealias} ]]; then
            /usr/vm/sbin/vmadm update ${zoneuuid} \
                alias=${zonename}${SDC_DATACENTER_HEADNODE_ID}
        fi
    fi
done

exit 0
