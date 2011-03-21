#!/usr/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All rights reserved.
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

function install_config_file
{
    option=$1
    target=$2

    # pull out those config options we want to keep
    filename=$(
        . ${USB_COPY}/config
        eval echo "\${${option}}"
    )

    if [[ -n ${filename} ]] && [[ -f "${USB_COPY}/config.inc/${filename}" ]]; then
        cp "${USB_COPY}/config.inc/${filename}" "${target}"
    fi
}

function update_datasets
{
    option=$1

    # pull out those config options we want to keep
    assets_ip=$(
        . ${USB_COPY}/config
        eval echo "\${${option}}"
    )

    # Rewrite the new local dataset url
    # Hardcoded global assets url?
    for file in $(ls ${USB_COPY}/datasets/*.dsmanifest); do
        /usr/bin/sed -i "" -e 's|"url": "https:.*/|"url": "http://$assets_ip/|' $file
    done
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

    echo -n "Importing zone template datasets... " >&${CONSOLE_FD}
    for template in $(echo ${CONFIG_headnode_initial_datasets} | tr ',' ' '); do
        ds=$(ls ${USB_PATH}/datasets/${template}*.zfs.bz2 | tail -1)
        [[ -z ${ds} ]] && fatal "Failed to find '${template}' dataset"
        echo -n "$(basename ${ds} .zfs.bz2) . "
        bzcat ${ds} | zfs recv -e zones || fatal "unable to import ${template}";
    done
    echo "done." >&${CONSOLE_FD}

    reboot
    exit 2
fi

if ( zoneadm list -i | grep -v "^global$" ); then
    ZONES=`zoneadm list -i | grep -v "^global$"`
else
    ZONES=
fi

LATESTTEMPLATE=''
for template in `ls /zones | grep smartos`; do
    LATESTTEMPLATE=${template}
done

USBZONES=`ls ${USB_COPY}/zones`
ALLZONES=`for x in ${ZONES} ${USBZONES}; do echo ${x}; done | sort -r | uniq | xargs`
CREATEDZONES=

# Create link for latest platform
create_latest_link

for zone in $ALLZONES; do
    if [[ -z $(echo "${ZONES}" | grep ${zone}) ]]; then

        # This is to move us to the next line past the login: prompt
        [[ -z "${CREATEDZONES}" ]] && echo "" >&${CONSOLE_FD}

        ${USB_COPY}/scripts/create-zone.sh ${zone}

        CREATEDZONES="${CREATEDZONES} ${zone}"
    fi
done

if [ -n "${CREATEDZONES}" ]; then
    # Wait for all the zones here instead of using create-zone -w
    # So that we can spin them all up in parallel and cook our laps
    for zone in ${CREATEDZONES}; do
        if [ -e /zones/${zone}/root/root/zoneinit ]; then
            echo -n "${zone}: waiting for zoneinit." >&${CONSOLE_FD}
            loops=0
            while [ -e /zones/${zone}/root/root/zoneinit ]; do
                sleep 10
                echo -n "." >&${CONSOLE_FD}
                loops=$((${loops} + 1))
                [ ${loops} -ge 59 ] && break
            done
            if [ ${loops} -ge 59 ]; then
                echo " timeout!" >&${CONSOLE_FD}
                ls -l /zones/${zone}/root/root >&${CONSOLE_FD}
            else
                echo " done." >&${CONSOLE_FD}
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
        which_agents=$(ls -1 ${USB_PATH}/ur-scripts/agents-*.sh | tail -n1)
        if [[ -n ${which_agents} ]]; then
            echo -n "Installing $(basename ${which_agents})... " >&${CONSOLE_FD}
            (cd /var/tmp ; bash ${which_agents})
            echo "done." >&${CONSOLE_FD}
        else
            fatal "No agents-*.sh found!"
        fi
    fi

    echo "==> Setup complete.  Press [enter] to get login prompt." >&${CONSOLE_FD}
    echo "" >&${CONSOLE_FD}
fi

exit 0
