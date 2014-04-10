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

shopt -s extglob

#---- setup state support
# "/var/lib/setup.json" support is duplicated in headnode.sh and
# upgrade_hooks.sh. These must be kept in sync.
# TODO: share these somewhere

SETUP_FILE=/var/lib/setup.json

function setup_state_add
{
    STATE=$1

    chmod 600 $SETUP_FILE
    cat "$SETUP_FILE" | json -e \
        "this.current_state = '$STATE';
         this.last_updated = new Date().toISOString();
         this.seen_states.push('$STATE');" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
}

function setup_state_mark_complete
{
    chmod 600 $SETUP_FILE
    # Update the setup state file with the new value
    cat "$SETUP_FILE" | json -e "this.complete = true;
         this.current_state = 'setup_complete';
         this.seen_states.push('setup_complete');
         this.last_updated = new Date().toISOString();" \
        | tee ${SETUP_FILE}.new
    mv ${SETUP_FILE}.new $SETUP_FILE
    chmod 400 $SETUP_FILE
    sysinfo -u
}

# Return 0 if the given setup stage has NOT been done, 1 otherwise.
# Usage:
#
#       if setup_state_not_seen "foo"; then
#           ...
#           setup_state_add "foo"
#       fi
function setup_state_not_seen
{
    local state=$1
    local seen=$(json -f ${SETUP_FILE} -e \
        "this.result = this.seen_states.filter(
            function(e) { return e === '$state' })[0]" | json result)
    if [[ -z "$seen" ]]; then
        return 0
    else
        return 1
    fi
}



#---- support functions

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

set_default_fw_rules() {
    [[ -f /var/fw/.default_rules_setup ]] && return

    local admin_cidr=$(ip_netmask_to_cidr $CONFIG_admin_network \
                       $CONFIG_admin_netmask)
    /usr/sbin/fwadm add -f - <<RULES
{
  "rules": [
  {
    "description": "allow pings to all VMs",
    "rule": "FROM any TO all vms ALLOW icmp type 8 code 0",
    "enabled": true,
    "global": true
  },
  {
    "description": "SDC zones: allow all UDP from admin net",
    "rule": "FROM subnet ${admin_cidr} TO tag smartdc_role ALLOW udp PORT all",
    "owner_uuid": "${CONFIG_ufds_admin_uuid}",
    "enabled": true
  },
  {
    "description": "SDC zones: allow all TCP from admin net",
    "rule": "FROM subnet ${admin_cidr} TO tag smartdc_role ALLOW tcp PORT all",
    "owner_uuid": "${CONFIG_ufds_admin_uuid}",
    "enabled": true
  }
  ]
}
RULES

    [[ $? -eq 0 ]] && touch /var/fw/.default_rules_setup
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
    # BASHSTYLED
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    export BASH_XTRACEFD=2
    set -o xtrace
fi

# BEGIN BASHSTYLED
USB_PATH=/mnt/`svcprop -p "joyentfs/usb_mountpoint" svc:/system/filesystem/smartdc:default`
USB_COPY=`svcprop -p "joyentfs/usb_copy_path" svc:/system/filesystem/smartdc:default`
# END BASHSTYLED

# Load config variables with CONFIG_ prefix
. /lib/sdc/config.sh
. /lib/sdc/network.sh
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

if [[ ! -d /usbkey/extra/joysetup ]]; then
    mkdir -p /usbkey/extra/joysetup
    cp /usbkey/scripts/joysetup.sh /usbkey/extra/joysetup
    cp /usbkey/scripts/agentsetup.sh /usbkey/extra/joysetup

    # Create a subset of the headnode config which will be downloaded by
    # compute nodes when they are setting up for the first time.
    NODE_CONFIG_KEYS='
        datacenter_name
        root_authorized_keys_file
        assets_admin_ip
        dns_domain
        dns_resolvers
        ntp_conf_file
        ntp_hosts
        swap
        rabbitmq
        root_shadow
        ufds_admin_ips
        ufds_admin_uuid
        dhcp_lease_time
        capi_client_url
        capi_http_admin_user
        capi_http_admin_pw
        zonetracker_database_path
        binder_admin_ips
        imgapi_admin_ips
        imgapi_domain
        fwapi_domain
        vmapi_admin_ips
        vmapi_domain
        '
    bash /lib/sdc/config.sh -json \
        | json -e '// compute_node_FOO -> FOO
            Object.keys(this).forEach(function (k) {
                var m = /^compute_node_(.*?)$/.exec(k);
                if (m) {
                    this[m[1]] = this[k]
                }
            });' $NODE_CONFIG_KEYS -j \
        | json -e "// Format as key='value'
            this.formatted = Object.keys(this).map(function (k) {
                return k + '=\\'' + this[k] + '\\'';
            }).join('\\n');" formatted \
        > /usbkey/extra/joysetup/node.config
fi

# print a banner on first boot indicating this is SDC7
if [[ -f /usbkey/banner && ! -x /opt/smartdc/agents/bin/apm ]]; then
    cr_once
    cat /usbkey/banner >&${CONSOLE_FD}
    echo "" >&${CONSOLE_FD}
fi

# HEAD-1371 is tool setup going to have to come after SAPI/config?
if [[ ! -d /opt/smartdc/bin ]]; then
    mkdir -p /opt/smartdc/bin
    cp /usbkey/tools/* /opt/smartdc/bin
    chmod 755 /opt/smartdc/bin/*
    mkdir -p /opt/smartdc/man
    cp -R /usbkey/tools-man/* /opt/smartdc/man/
    find /opt/smartdc/man/ -type f -exec chmod 444 {} \;
    mkdir -p /opt/smartdc/node_modules
    (cd /opt/smartdc/node_modules && tar -xf /usbkey/tools-modules.tar)
fi

if [[ ! -d /opt/smartdc/sdcadm ]]; then
    /usbkey/sdcadm-install.sh || /bin/true
fi

set_default_fw_rules

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
            setup_state_add "agents_installed"
        else
            printf_log "%-58s" "installing $(basename ${which_agents})... "
            (cd /var/tmp ; bash ${which_agents} >&4 2>&1)
        fi
        printf_timer "%4s (%ss)\n" "done"
    else
        fatal "No agents-*.sh found!"
    fi

    # Put the agents in a place where they will be available to compute nodes.
    if [[ ! -d /usbkey/extra/agents ]]; then
        mkdir -p /usbkey/extra/agents
        cp -Pr /usbkey/ur-scripts/agents-*.sh /usbkey/extra/agents/
        ln -s $(basename ${which_agents}) /usbkey/extra/agents/latest
    fi
fi

# headnode.sh normally does the initial setup of the headnode when it first
# boots.  This creates the core zones, installs agents, etc.
#
# We want to be careful here since, sdc-restore -F will also run this
# headnode.sh script (with the restore parameter).

CREATEDZONES=
CREATEDUUIDS=

# Create link for latest platform
create_latest_link


# Update /usbkey/datasets/ manifests usage of the all-zero's owner UUID
# placeholder, to the actual admin UUID for this DC.
for manifest in $(ls -1 ${USB_COPY}/datasets/*manifest); do
    tmpmanifest=/var/tmp/$(basename manifest)
    json -f ${manifest} \
        -e "if (this.creator_uuid === '00000000-0000-0000-0000-000000000000')
                this.creator_uuid = '$CONFIG_ufds_admin_uuid';
            if (this.owner === '00000000-0000-0000-0000-000000000000')
                this.owner = '$CONFIG_ufds_admin_uuid';" \
        > ${tmpmanifest}
    [[ $? != 0 ]] && fatal "Could not update owner in $manifest"
    mv ${tmpmanifest} ${manifest}
done

# Install the core headnode zones

function create_zone {
    zone=$1
    new_uuid=$(uuid -v4)

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
        # PCFS casing. sigh.
        ds_name=$(cat ${USB_COPY}/zones/${zone}/dataset)
        [[ -z ${ds_name} ]] && \
            fatal "No dataset specified in ${USB_COPY}/zones/${zone}/dataset"
        ds_manifest=$(ls ${USB_COPY}/datasets/${ds_name})
        [[ -z ${ds_manifest} ]] && fatal "No manifest found at ${ds_manifest}"
        ds_basename=$(echo "${ds_name}" | sed -e "s/\.zfs\.imgmanifest$//" \
            -e "s/\.dsmanifest$//" -e "s/\.imgmanifest$//")
        ds_filename=$(ls ${USB_COPY}/datasets/${ds_basename}.zfs+(.bz2|.gz) \
                      | head -1)
        [[ -z ${ds_filename} ]] && fatal "No filename found for ${ds_name}"
        ds_uuid=$(json uuid < ${ds_manifest})
        [[ -z ${ds_uuid} ]] && fatal "No uuid found for ${ds_name}"

        # imgadm exits non-zero when the dataset is already imported, we need to
        # work around that.
        if [[ ! -d /zones/${ds_uuid} ]]; then
            printf_log "%-58s" "importing: $(echo ${ds_name} | cut -d'.' -f1) "
            imgadm install -m ${ds_manifest} -f ${ds_filename}
            printf_timer "done (%ss)\n" >&${CONSOLE_FD}
        fi
    fi

    if [[ "$CONFIG_coal" == "true" && "$zone" == "ufds" && $upgrading == 1 ]]
    then
        printf_log "%-58s" "coal pre-ufds sleep... "
        sleep 30
        printf_log "done (30)\n" >&${CONSOLE_FD}
        prev_t=$(date +%s)
    fi

    if [[ ${restore} == 0 ]]; then
        printf_log "%-58s" "creating zone ${existing_uuid}${zone}... "
    else
        # alternate format for sdc-restore
        printf "%s" "creating zone ${existing_uuid}${zone}... " \
            >&${CONSOLE_FD}
    fi

    dtrace_pid=
    if [[ -x /usbkey/tools/zoneboot.d \
        && ${CONFIG_dtrace_zone_setup} == "true" ]]; then

        /usbkey/tools/zoneboot.d ${new_uuid} \
            >/var/log/${new_uuid}.setup.json 2>&1 &
        dtrace_pid=$!
    fi


    local payload_file=/var/tmp/${zone}_payload.json
    if [[ ${USE_SAPI} && -f ${USB_COPY}/services/${zone}/service.json ]]; then
        echo "Deploy zone ${zone} (payload via SAPI)"
        local sapi_url=http://${CONFIG_sapi_admin_ips}
        [[ $upgrading == 1 ]] && UPGRADING="yes"

        # HEAD-1327 for the first manatee, we want ONE_NODE_WRITE_MODE turned on
        if [[ ${zone} == "manatee" ]]; then
            export ONE_NODE_WRITE_MODE="true"
        fi

        # BASHSTYLED
        UPGRADING=${UPGRADING} ${USB_COPY}/scripts/sdc-deploy.js ${sapi_url} ${zone} ${new_uuid} > ${payload_file}

        # don't pollute things for everybody else
        if [[ ${zone} == "manatee" ]]; then
            unset ONE_NODE_WRITE_MODE
            export ONE_NODE_WRITE_MODE
        fi
    else
        echo "Deploy zone ${zone} (payload via build-payload.js)"
        ${USB_COPY}/scripts/build-payload.js ${zone} ${new_uuid} \
        > ${payload_file}
    fi

    cat ${payload_file} | vmadm create

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
            # BASHSTYLED
            fatal "Failed to create ${zone}: setup timed out after ${delta_t} seconds."
        elif [[ -f ${zonepath}/root/var/svc/setup_complete ]]; then
            printf_timer "%4s (%ss)\n" "done"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
        elif [[ -f ${zonepath}/root/var/svc/setup_failed ]]; then
            printf_log "failed\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            # BASHSTYLED
            fatal "Failed to create ${zone}: setup failed after ${delta_t} seconds."
        elif [[ -n $(svcs -xvz ${new_uuid}) ]]; then
            printf_log "svcs-fail\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            # BASHSTYLED
            fatal "Failed to create ${zone}: 'svcs -xv' not clear after ${delta_t} seconds."
        else
            printf_log "timeout\n"
            [[ -n ${dtrace_pid} ]] && kill ${dtrace_pid}
            # BASHSTYLED
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

    # Success, set created_${zone}=1 in case there are other things we want
    # to do only when we created this thing.
    eval "created_${zone}=1"

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

function sdc_init_application
{
    [[ -f ${USB_COPY}/application.json ]] || fatal "No application.json"

    if setup_state_not_seen "sapi_setup"; then
        ${USB_COPY}/scripts/sdc-init.js
        setup_state_add "sapi_setup"
    fi
}

function bootstrap_sapi
{
    if setup_state_not_seen "sapi_bootstrap"; then
        echo "Bootstrapping SAPI into SAPI"
        local sapi_uuid=$(vmadm lookup tags.smartdc_role=sapi)
        zlogin ${sapi_uuid} /usr/bin/bash <<HERE
export ZONE_ROLE=sapi
export ASSETS_IP=${CONFIG_assets_admin_ip}
export CONFIG_AGENT_LOCAL_MANIFESTS_DIRS=/opt/smartdc/\${ZONE_ROLE}
source /opt/smartdc/boot/lib/util.sh
sapi_adopt
setup_config_agent
upload_values
download_metadata
write_initial_config
registrar_setup
HERE
        setup_state_add "sapi_bootstrapped"
    fi
}

if [[ -z ${skip_zones} ]]; then

    # If the zone image is incremental, you'll need to manually setup the import
    # here for the origin dataset for now. The way to do this is add the name
    # and uuid to build.spec's datasets.
    if [[ -f /usbkey/datasets/img_dependencies ]]; then
        for name in $(cat /usbkey/datasets/img_dependencies); do
            imgadm install -f \
                "$(ls -1 /usbkey/datasets/${name}.zfs.{gz,bz2} | head -1)" \
                -m /usbkey/datasets/${name}.dsmanifest
        done
    fi

    # These are here in the order they'll be brought up.
    create_zone assets
    create_zone sapi

    # get SAPI standing up, then use that.
    sdc_init_application
    export USE_SAPI="true"

    create_zone binder
    # here we bootstrap SAPI to be aware of itself, including writing out
    # its standard DNS config.
    bootstrap_sapi

    create_zone manatee
    create_zone moray
    create_zone amonredis
    create_zone redis
    create_zone ufds
    create_zone workflow
    create_zone amon
    create_zone sdc
    create_zone papi
    create_zone napi
    create_zone rabbitmq
    create_zone imgapi
    create_zone cnapi
    create_zone dhcpd
    create_zone fwapi
    create_zone vmapi
    create_zone ca
    create_zone mahi
    create_zone adminui
fi

setup_state_add "sdczones_created"

# copy sdc-manatee tools to GZ - see MANATEE-86
echo "==> Copying manatee tools to GZ."
manatee=$(vmadm lookup tags.smartdc_role=manatee | tail -1)
for file in $(ls /zones/${manatee}/root/opt/smartdc/manatee/bin/sdc*); do
    tool=$(basename ${file} .js)
    mv ${file} /opt/smartdc/bin/${tool}
done

# Copy sapiadm into the GZ from the SAPI zone
zone_uuid=$(vmadm lookup tags.smartdc_role=sapi | head -n 1)
if [[ -n ${zone_uuid} ]]; then
    from_dir=/zones/${zone_uuid}/root/opt/smartdc/config-agent/cmd
    to_dir=/opt/smartdc/bin
    rm -f ${to_dir}/sapiadm
    ln -s ${from_dir}/sapiadm.js ${to_dir}/sapiadm
fi


# Import the images used for SDC services into IMGAPI.
function import_smartdc_service_images {

    # If the zone image is incremental, you'll need to manually setup the import
    # here for the origin dataset for now. The way to do this is add the name
    # and uuid to build.spec's datasets.
    if [[ -f /usbkey/datasets/img_dependencies ]]; then
        for name in $(cat /usbkey/datasets/img_dependencies); do
            /opt/smartdc/bin/sdc-imgadm import --skip-owner-check \
                -f "$(ls -1 /usbkey/datasets/${name}.zfs.{gz,bz2} | head -1)" \
                -m /usbkey/datasets/${name}.dsmanifest
        done
    fi

    for manifest in $(ls -1 ${USB_COPY}/datasets/*.imgmanifest); do
        local is_smartdc_service=$(cat $manifest | json tags.smartdc_service)
        if [[ "$is_smartdc_service" != "true" ]]; then
            # /usbkey/datasets often has non-core images. Don't import those
            # here. This includes any additional datasets included in
            # build.spec#datasets.
            continue
        fi
        local uuid=$(cat ${manifest} | json uuid)

        # We'll retry up to 3 times on errors reaching IMGAPI.
        local ok=false
        local retries=0
        while [[ ${ok} == "false" && ${retries} -lt 3 ]]; do
            local status=$(/opt/smartdc/bin/sdc-imgapi /images/${uuid} \
                           | head -1 | awk '{print $2}')
            if [[ "${status}" == "404" ]]; then
                # The core images all have .zfs.imgmanifest extensions.

                # BASHSTYLED
                local file_basename=$(echo "${manifest}" | sed -e "s/\.zfs\.imgmanifest$//" \
                    -e "s/\.dsmanifest$//" -e "s/\.imgmanifest$//")
                local file=$(ls -1 ${file_basename}.zfs+(.bz2|.gz) | head -1)

                if [[ -z ${file} ]]; then
                    # BASHSTYLED
                    fatal "Unable to find file for ${manifest} in: $(ls -l /usbkey/datasets)"
                fi

                # BASHSTYLED
                echo "Importing SDC service image ${uuid} (${manifest}, ${file}) into IMGAPI."
                [[ -f ${file} ]] || fatal "Image file ${file} not found."
                # Skip the check that "owner" exists in UFDS during setup
                # b/c if this is not the DC with the UFDS master, then the
                # admin user will not have been replicated yet.
                /opt/smartdc/bin/sdc-imgadm import --skip-owner-check \
                    -m ${manifest} -f ${file}
                ok=true
            elif [[ "${status}" == "200" ]]; then
                # exists
            # BASHSTYLED
                echo "Skipping import of SDC service image ${uuid}: already in IMGAPI."
                ok=true
            else
                retries=$((${retries} + 1))
            fi
        done
        if [[ ${ok} != "true" ]]; then
            fatal "Unable to import image ${uuid} after ${retries} tries."
        fi
    done
}


if setup_state_not_seen "import_smartdc_service_images"; then
    # Import bootstrapped core images into IMGAPI.
    import_smartdc_service_images
    setup_state_add "import_smartdc_service_images"
fi



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
            printf_log \
            "Warning: services in the following zones are still not running:\n"
            svcs -Zx | nawk '{if ($1 == "Zone:") print $2}' | sort -u | \
                tee -a /tmp/upgrade_progress >&${CONSOLE_FD}
        fi

        # The SMF services should now be up, so we wait for the setup scripts
        # in each of the created zones to be completed (these run in the
        # background for all but assets so may not have finished with
        # the services)
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

    #
    # Once SDC has finished setup, upgrade SAPI to full mode.  This call informs
    # SAPI that its dependent SDC services are ready and that it should store
    # the SDC deployment configuration persistently.
    #
    i=0
    sresult=1
    while [[ ${sresult} -gt 0 && ${i} -lt 48 ]]; do
        /opt/smartdc/bin/sdc-sapi /mode?mode=full -X POST -m 5 --fail
        sresult=$?
        if [[ ${sresult} -ne 0 ]]; then
            printf_log "%-58s" "SAPI isn't in full mode yet..."
            sleep 5
        fi
        i=$((${i} + 1))
    done

    # Run a post-install script. This feature is not formally supported in SDC
    if [ -f ${USB_COPY}/scripts/post-install.sh ]; then
        printf_log "%-58s" "Executing post-install script..."
        bash ${USB_COPY}/scripts/post-install.sh
        printf_log "done\n"
    fi

    printf_timer "%-58sdone (%ss)\n" "completing setup..."

    if [ $restore == 0 ]; then
        echo "" >&${CONSOLE_FD}
        if [[ $upgrading == 1 ]]; then
            printf_timer "FROM_START" \
                "initial setup complete (in %s seconds).\n"
        else
            printf_timer "FROM_START" \
"==> Setup complete (in %s seconds). Press [enter] to get login prompt.\n"
        fi
        echo "" >&${CONSOLE_FD}
    fi
fi

# Install all AMON probes, but don't fail setup if it doesn't work
/opt/smartdc/bin/sdc-amonadm update || /bin/true

if [[ $upgrading == 1 ]]; then
    printf_log "%-58s\n" "running post-setup upgrade tasks... "
    /var/upgrade_headnode/upgrade_hooks.sh "post" \
        4>/var/upgrade_headnode/finish_post.log
    printf_log "%-58s" "completed post-setup upgrade tasks... "
    printf_timer "%4s (%ss)\n" "done"

    # Note: It is 'upgrade_hooks.sh's responsibility to do
    # the equivalent of 'setup_state_mark_complete' when it is done.
else
    setup_state_mark_complete
    rm -f /tmp/.ur-startup
    svcadm restart ur
fi

exit 0
