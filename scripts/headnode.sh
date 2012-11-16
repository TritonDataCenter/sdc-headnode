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
export HEADNODE_SETUP_START=$(date +%s)

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

# time to wait for each zone to setup (in seconds)
ZONE_SETUP_TIMEOUT=180

function fatal
{
    printf_log "%-80s\r" " "
    printf_log "headnode configuration: fatal error: $*\n"
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

# This takes printf args, and will add one additional arg which is the time
# since the last run (or from start if first arg is "FROM_START")
function printf_timer
{
    local p=${prev_t}

    [[ -z ${p} ]] && p=${HEADNODE_SETUP_START}
    if [[ $1 == "FROM_START" ]]; then
        p=${HEADNODE_SETUP_START}
        shift
    fi

    now=$(date +%s)
    delta_t=$((${now} - ${p}))
    if [[ -n ${CONFIG_show_setup_timers} ]]; then
        cr_once

        # This mess just runs printf again with the same args we were passed
        # adding the delta argument.
        if [[ $upgrading == 1 ]]; then
            eval printf \
                $(for arg in "$@"; do
                    echo "\"${arg}\""
                done; echo \"${delta_t}\") | \
                tee -a /tmp/upgrade_progress >&${CONSOLE_FD}
        else
            eval printf \
                $(for arg in "$@"; do
                    echo "\"${arg}\""
                done; echo \"${delta_t}\") \
            >&${CONSOLE_FD}
        fi
    fi
    prev_t=${now}
}

function printf_log
{
    if [[ $upgrading == 1 ]]; then
        printf "$@" | tee -a /tmp/upgrade_progress >&${CONSOLE_FD}
    else
        printf "$@" >&${CONSOLE_FD}
    fi
}

# Zoneinit is a pig and makes us reboot the zone, this allows us to bypass it
# entirely well still getting all the things done that it would have done that
# we care about.
function fake_zoneinit
{
    local zoneroot=$1

    if [[ -z ${zoneroot} || ! -d ${zoneroot} ]]; then
        fatal "fake_zoneinit(): bad zoneroot: ${zoneroot}"
    fi

    rm ${zoneroot}/var/adm/utmpx ${zoneroot}/var/adm/wtmpx ; touch ${zoneroot}/var/adm/wtmpx
    rm -rf ${zoneroot}/var/svc/log/*
    rm -rf ${zoneroot}/root/zone*
    cat > ${zoneroot}/root/zoneinit <<EOF
#!/usr/bin/bash

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin
PKGSRC_REPO=http://pkgsrc.joyent.com/sdc6/2011Q4/i386/All

# Unset passwords that might have been mistakenly left in datasets (yes really)
passwd -N root
passwd -N admin

# Then disable services we don't ever need (disabling ssh is important so
# we don't need to bother generating an ssh key for this zone)
svcadm disable ssh:default
svcadm disable inetd

# Remove these default keys (that are again in the dataset!)
rm -f /etc/ssh/ssh_*key*

upgrading=0

echo "PKG_PATH=\${PKGSRC_REPO}" > /opt/local/etc/pkg_install.conf
echo "\${PKGSRC_REPO}" > /opt/local/etc/pkgin/repositories.conf
pkgin -V -f -y update || true

# start mdata so we run the user-script
svcadm enable mdata:fetch

# suicide
rm -f /root/zoneinit
svccfg delete zoneinit

exit 0
EOF

    chmod 555 ${zoneroot}/root/zoneinit
}


# TODO: add something in that adds packages.

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
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
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

    if ! ${USB_PATH}/scripts/joysetup.sh; then
        # copy the log out just in case we made it as far as setting up /var
        cp /tmp/joysetup.* /zones
        exit 1
    fi

    # copy the log out to /var so we don't lose on reboot
    cp /tmp/joysetup.* /zones

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

# Create a subset of the headnode config which will be downloaded by compute
# nodes when they are setting up for the first time.
read -r -d '' KEYS <<ENDKEYS || true
datacenter_name
root_authorized_keys_file
assets_admin_ip
dns_domain
dns_resolvers
compute_node_ntp_conf_file
compute_node_ntp_hosts
compute_node_swap
rabbitmq
root_shadow
ufds_admin_ips
ufds_admin_uuid
dhcp_lease_time
capi_client_url
capi_http_admin_user
capi_http_admin_pw
zonetracker_database_path
ENDKEYS

KEYS=$(echo $KEYS | tr -d '\n')

read -r -d '' SUBSETJS <<ENDSUBSETJS || true
var newobj = [];
'$KEYS'.split(/\\s+/).forEach(function (k) {
    var v;
    if (k.match(/^compute_node_/)) {
        v = this[k];
        k = k.split(/^compute_node_/)[1];
    } else {
        v = this[k];
    }
    if (!v) {
        return;
    }
    newobj.push(k + "='" + v + "'");
});
newobj = newobj.join("\\n");
ENDSUBSETJS

if [[ ! -d /usbkey/extra/joysetup ]]; then
    mkdir -p /usbkey/extra/joysetup
    bash /lib/sdc/config.sh -json \
        | json -e "$SUBSETJS" newobj \
        > /usbkey/extra/joysetup/node.config
    cp /usbkey/scripts/joysetup.sh /usbkey/extra/joysetup
    cp /usbkey/scripts/agentsetup.sh /usbkey/extra/joysetup
fi

# Put the agents in a place where they will be available to compute nodes.
if [[ ! -d /usbkey/extra/agents ]]; then
    mkdir -p /usbkey/extra/agents
    cp -Pr /usbkey/ur-scripts/agents-*.sh /usbkey/extra/agents/
    ln -s `ls /usbkey/extra/agents | tail -n 1` /usbkey/extra/agents/latest
fi

# Setup the pkgsrc directory for the core zones to pull files from.
# We need to switch the name from 2010q4 to 2010Q4, so we just link the files
# into one with the correct name.  Thanks PCFS!
for dir in $(ls ${USB_COPY}/extra/pkgsrc/ | grep q); do
    upper=$(echo "${dir}" | tr [:lower:] [:upper:])
    mkdir -p ${USB_COPY}/extra/pkgsrc/${upper}
    (cd ${USB_COPY}/extra/pkgsrc/${upper} && ln -f ${USB_COPY}/extra/pkgsrc/${dir}/* .)
done

# print a banner on first boot indicating this is SDC7
if [[ -f /usbkey/banner && ! -x /opt/smartdc/agents/bin/apm ]]; then
    cr_once
    cat /usbkey/banner >&${CONSOLE_FD}
    echo "" >&${CONSOLE_FD}
fi

if [[ ! -d /opt/smartdc/bin ]]; then
    mkdir -p /opt/smartdc/bin
    cp /usbkey/tools/* /opt/smartdc/bin
    chmod 755 /opt/smartdc/bin/*
    mkdir -p /opt/smartdc/man
    cp -R /usbkey/tools-man/* /opt/smartdc/man/
    find /opt/smartdc/man/ -type f -exec chmod 444 {} \;

    mkdir -p /opt/smartdc/manta
    (cd /opt/smartdc && tar -xjf ${USB_COPY}/extra/manta/manta.tar.bz2)
    for file in $(ls /opt/smartdc/manta/bin/manta*); do

        # Strip trailing .js if present
        tool=$(basename ${file} .js)

        ln -s ${file} /opt/smartdc/bin/${tool}
    done
fi

printf_timer "%-58sdone (%ss)\n" "preparing for setup..."

if [[ -x /var/upgrade_headnode/upgrade_hooks.sh ]]; then
    upgrading=1
    printf_log "%-58s\n" "running pre-setup upgrade tasks... "
    /var/upgrade_headnode/upgrade_hooks.sh "pre" \
        4>/var/upgrade_headnode/finish_pre.log
    printf_log "%-58s" "completed pre-setup upgrade tasks... "
    printf_timer "%4s (%ss)\n" "done"
fi

# For dev/debugging, you can set the SKIP_AGENTS environment variable.
if [[ -z ${SKIP_AGENTS} && ! -x "/opt/smartdc/agents/bin/apm" ]]; then
    cr_once
    # Install the agents here so initial zones have access to metadata.
    which_agents=$(ls -t ${USB_PATH}/ur-scripts/agents-*.sh \
        | grep -v -- '-hvm-' | head -1)
    if [[ -n ${which_agents} ]]; then
        if [ $restore == 0 ]; then
            printf_log "%-58s" "installing $(basename ${which_agents})... "
            (cd /var/tmp ; bash ${which_agents})
        else
            printf_log "%-58s" "installing $(basename ${which_agents})... "
            (cd /var/tmp ; bash ${which_agents} >&4 2>&1)
        fi
        printf_timer "%4s (%ss)\n" "done"
    else
        fatal "No agents-*.sh found!"
    fi
fi

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
    if [[ -f ${USB_COPY}/zones/${zone}/dataset ]]; then
        ds_name=$(cat ${USB_COPY}/zones/${zone}/dataset)
        [[ -z ${ds_name} ]] && fatal "No dataset specified in ${USB_COPY}/zones/${zone}/dataset"
        ds_manifest=$(ls ${USB_COPY}/datasets/${ds_name}.dsmanifest)
        [[ -z ${ds_manifest} ]] && fatal "No manifest found for ${ds_name}"
        ds_filename=$(ls ${USB_COPY}/datasets/${ds_name}.zfs.bz2)
        [[ -z ${ds_filename} ]] && fatal "No filename found for ${ds_name}"
        ds_uuid=$(json uuid < ${ds_manifest})
        [[ -z ${ds_uuid} ]] && fatal "No uuid found for ${ds_name}"

        # imgadm exits non-zero when the dataset is already imported, we need to
        # work around that.
        if [[ ! -d /zones/${ds_uuid} ]]; then
            printf_log "%-58s" "importing SMI: ${ds_name}"
            imgadm install -m ${ds_manifest} -f ${ds_filename}
            printf_timer "done (%ss)\n" >&${CONSOLE_FD}
        fi
    fi

    if [[ ${restore} == 0 ]]; then
        printf_log "%-58s" "creating zone ${existing_uuid}${zone}... "
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
    if [[ -f ${USB_COPY}/default/configure.common ]]; then
        # extra include file for core zones.
        rm -f ${dir}/configure.common
        ln ${USB_COPY}/default/configure.common ${dir}/configure.common
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

    dtrace_pid=
    if [[ -x /usbkey/tools/zoneboot.d \
        && ${CONFIG_dtrace_zone_setup} == "true" ]]; then

        /usbkey/tools/zoneboot.d ${new_uuid} >/var/log/${new_uuid}.setup.json 2>&1 &
        dtrace_pid=$!
    fi

    # by breaking this up we're able to use fake_zoneinit instead of zoneinit
    NODE_PATH="/usr/node_modules:${NODE_PATH}" \
        ${USB_COPY}/scripts/build-payload.js ${zone} ${new_uuid} | vmadm create

    # for joyent minimal we can autoboot and have already faked out zoneinit
    if [[ $(json brand < ${USB_COPY}/zones/${zone}/create.json) != "joyent-minimal" ]]; then
        fake_zoneinit /zones/${new_uuid}/root
        vmadm boot ${new_uuid}
    fi

    local loops=
    local zonepath=
    if [[ ${CONFIG_serialize_setup} == "true" ]]; then
        loops=0
        zonepath=$(vmadm get ${new_uuid} | json zonepath)
        if [[ -z ${zonepath} ]]; then
            fatal "Unable to find zonepath for ${new_uuid}"
        fi

        while [[ ! -f ${zonepath}/root/var/svc/setup_complete \
            && ! -f ${zonepath}/root/var/svc/setup_failed \
            && $loops -lt ${ZONE_SETUP_TIMEOUT} ]]; do

            sleep 1
            loops=$((${loops} + 1))
        done

        if [[ ${loops} -lt ${ZONE_SETUP_TIMEOUT} \
            && -f ${zonepath}/root/var/svc/setup_complete ]]; then

            # Got here and complete, now just wait for services.
            while [[ -n $(svcs -xvz ${new_uuid}) && \
                $loops -lt ${ZONE_SETUP_TIMEOUT} ]]; do
                sleep 1
                loops=$((${loops} + 1))
            done
        fi

        delta_t=$(($(date +%s) - ${prev_t}))  # For the fail cases
        if [[ ${loops} -ge ${ZONE_SETUP_TIMEOUT} ]]; then
            printf_log "timeout\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            fatal "Failed to create ${zone}: setup timed out after ${delta_t} seconds."
        elif [[ -f ${zonepath}/root/var/svc/setup_complete ]]; then
            printf_timer "%4s (%ss)\n" "done"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
        elif [[ -f ${zonepath}/root/var/svc/setup_failed ]]; then
            printf_log "failed\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            fatal "Failed to create ${zone}: setup failed after ${delta_t} seconds."
        elif [[ -n $(svcs -xvz ${new_uuid}) ]]; then
            printf_log "svcs-fail\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            fatal "Failed to create ${zone}: 'svcs -xv' not clear after ${delta_t} seconds."
        else
            printf_log "timeout\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            fatal "Failed to create ${zone}: timed out after ${delta_t} seconds."
        fi
    fi

    CREATEDZONES="${CREATEDZONES} ${zone}"
    CREATEDUUIDS="${CREATEDUUIDS} ${new_uuid}"

    if [[ $upgrading == 1 ]]; then
        printf_log "%-58s" "upgrading zone $zone... "
        /var/upgrade_headnode/upgrade_hooks.sh ${zone} ${new_uuid} \
            4>/var/upgrade_headnode/finish_${zone}.log
        printf_timer "%4s (%ss)\n" "done"
    fi

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


if [[ -z ${skip_zones} ]]; then
    printf_timer "%-58s%s (%ss)\n" "standby/restore check..." "done"
    # Create assets first since others will download stuff from here.
    export ASSETS_IP=${CONFIG_assets_admin_ip}
    # These are here in the order they'll be brought up.
    create_zone assets
    create_zone zookeeper
    create_zone manatee
    create_zone moray
    create_zone redis
    create_zone ufds
    create_zone workflow
    create_zone amon
    create_zone napi
    create_zone rabbitmq
    create_zone imgapi
    create_zone cnapi
    create_zone dhcpd
    create_zone dapi
    create_zone fwapi
    create_zone vmapi
    create_zone ca
    create_zone adminui
fi



function import_core_datasets {
    local manifests=$(ls /usbkey/datasets/*.*manifest)
    for manifest in $manifests; do
        local uuid=$(json uuid < $manifest)
        local status=$(sdc-imgapi /images/$uuid | head -1 | awk '{print $2}')
        if [[ "$status" == "404" ]]; then
            local file=${manifest%\.*}.zfs.bz2
            echo "Importing image $uuid ($manifest, $file) into IMGAPI."
            [[ -f $file ]] || fatal "Image $uuid file $file not found."
            sdc-imgapi /images/$uuid?action=import -d @$manifest
            sdc-imgapi /images/$uuid/file -T $file
            sdc-imgapi /images/$uuid?action=activate -X POST
        elif [[ "$status" == "200" ]]; then
            echo "Skipping import of image $uuid: already in IMGAPI."
        else
            echo "Error checking if image $uuid is in IMGAPI: HTTP $status"
        fi
    done
}


# Import bootstrapped core images into IMGAPI.
import_core_datasets



if [[ -n ${CREATEDZONES} ]]; then
    if [[ ${CONFIG_serialize_setup} != "true" ]]; then

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
                printf_log "%-58s%s\r" "${msg}" "${nstarting}"
            fi
            sleep 5
            i=`expr $i + 1`
        done
        if [[ ${restore} == 0 ]]; then
            printf_log "%-58s%s\n" "${msg}" "done"
        else
            # alternate formatting when restoring (sdc-restore)
            printf "%s%-20s\n" "${msg}" "done" >&${CONSOLE_FD}
        fi

        if [ $nstarting -gt 1 ]; then
            printf_log "Warning: services in the following zones are still not running:\n"
            svcs -Zx | nawk '{if ($1 == "Zone:") print $2}' | sort -u | \
                tee -a /tmp/upgrade_progress >&${CONSOLE_FD}
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
                printf_log "%-58s%s\r" "${msg}" "${nsettingup}"
            fi
            i=$((${i} + 1))
            sleep 5
            nsettingup=$(num_not_setup ${CREATEDUUIDS})
        done

        if [[ ${nsettingup} -gt 0 ]]; then
            printf_log "%-58s%s\n" "${msg}" "failed"
            fatal "Warning: some zones did not finish setup, installation " \
                "has failed."
        elif [[ ${restore} == 0 ]]; then
            printf_log "%-58s%s\n" "${msg}" "done"
        else
            # alternate formatting when restoring (sdc-restore)
            printf "%s%-20s\n" "${msg}" "done"  >&${CONSOLE_FD}
        fi
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
        printf_log "%-58s" "Executing post-install script..."
        bash ${USB_COPY}/scripts/post-install.sh
        printf_log "done\n"
    fi

    printf_timer "%-58sdone (%ss)\n" "completing setup..."

    if [ $restore == 0 ]; then
        echo "" >&${CONSOLE_FD}
        if [ $standby == 1 ]; then
            echo "Restoring standby headnode" >&${CONSOLE_FD}
        else
            if [[ $upgrading == 1 ]]; then
                printf_timer "FROM_START" \
                    "initial setup complete (in %s seconds).\n"
            else
                printf_timer "FROM_START" \
"==> Setup complete (in %s seconds). Press [enter] to get login prompt.\n"
            fi
            # Explicit marker file that headnode initial setup completed
            # successfully.
            touch /var/svc/setup_complete
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

if [[ $upgrading == 1 ]]; then
    printf_log "%-58s\n" "running post-setup upgrade tasks... "
    /var/upgrade_headnode/upgrade_hooks.sh "post" \
        4>/var/upgrade_headnode/finish_post.log
    printf_log "%-58s" "completed post-setup upgrade tasks... "
    printf_timer "%4s (%ss)\n" "done"
fi

#
# XXX this was commented out for HEAD-1048 as it depends on MAPI.  See HEAD-1051
#
#if [[ -f ${USB_COPY}/webinfo.tar && ! -d /opt/smartdc/webinfo ]]; then
#    ( mkdir -p /opt/smartdc && cd /opt/smartdc  && cat ${USB_COPY}/webinfo.tar \
#        | tar -xf - )
#fi
#
#( svccfg import /opt/smartdc/webinfo/smf/smartdc-webinfo.xml || /usr/bin/true )

exit 0
