#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2017 Joyent, Inc.
#

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
    local seen
    seen=$(json -f ${SETUP_FILE} -e "this.result = this.seen_states.filter(
        function(e) { return e === '$state' })[0]" result)
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

        eval printf \
            $(for arg in "$@"; do
                echo "\"${arg}\""
            done; echo \"${delta_t}\") \
        >&${CONSOLE_FD}
    fi
    prev_t=${now}
}

function printf_log
{
    printf "$@" >&${CONSOLE_FD}
}


function usbkey_dataset_exists
{
    if zfs list -H -o name | grep '^zones/usbkey$' > /dev/null; then
        return 0
    else
        return 1
    fi
}

function usbkey_dataset_create
{
    printf_log "%-56s" "adding volume: usbkey"

    local zpoolHealth
    zpoolHealth=$(zpool list -H -o health zones)
    [[ "$zpoolHealth" == "ONLINE" ]] || \
        fatal "'zones' zpool state is not ONLINE: $zpoolHealth"

    zfs create -o mountpoint=legacy zones/usbkey || \
        fatal "failed to create the usbkey dataset"

    printf_log "%4s\n" "done"
}


set_default_fw_rules() {
    local fw_default_v
    if [[ -f /var/fw/.default_rules_setup ]]; then
        read fw_default_v < /var/fw/.default_rules_setup || true
    else
        fw_default_v=0
    fi

    # Handle empty files from before we started versioning default rules
    if [[ -z $fw_default_v ]]; then
        fw_default_v=1
    fi

    local admin_cidr
    admin_cidr=$(ip_netmask_to_cidr $CONFIG_admin_network $CONFIG_admin_netmask)

    if [[ $fw_default_v -lt 1 ]]; then
        /usr/sbin/fwadm add -f - <<RULES
{
  "rules": [
  {
    "description": "allow all ICMPv4 types",
    "rule": "FROM any TO all vms ALLOW icmp type all",
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

        [[ $? -ne 0 ]] && return 1
        echo 1 > /var/fw/.default_rules_setup
    fi

    if [[ $fw_default_v -lt 2 ]]; then
        # When initially upgrading, firewaller will fail to sync this rule
        # and skip it on each sync until FWAPI is upgraded to support IPv6.
        # We return 0 if fwadm fails, in case the platform hasn't been
        # upgraded yet. We'll succeed after a platform upgrade.
        /usr/sbin/fwadm add -f - <<RULES || return 0
{
  "rules": [
  {
    "description": "allow all ICMPv6 types",
    "rule": "FROM any TO all vms ALLOW icmp6 type all",
    "enabled": true,
    "global": true
  }
  ]
}
RULES

        [[ $? -ne 0 ]] && return 1
        echo 2 > /var/fw/.default_rules_setup
    fi
}


# TODO: add something in that adds packages.

trap 'errexit $?' EXIT

#
# On initial install, do the extra logging, but for restore, we want cleaner
# output.
#
restore=0
if [[ $# == 0 ]]; then
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
        cp /tmp/joysetup.* /zones/
        exit 1
    fi

    # copy the log out to /var so we don't lose on reboot
    cp /tmp/joysetup.* /zones/

    usbkey_dataset_create

    printf "%4s\n" "done" >&${CONSOLE_FD}

    reboot
    exit 2

elif ! usbkey_dataset_exists; then
    # If we are converting from a CN to an HN, the zones/usbkey dataset
    # will not have been created when the zpool was created. We'll have needed
    # it earlier (e.g. for the filesystem/smartdc and identity:node svcs):
    # so create it, then reboot.
    usbkey_dataset_create

    printf_log "%4s\n" "done"

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
    cp \
        /usbkey/scripts/joysetup.sh \
        /usbkey/scripts/agentsetup.sh \
        /usbkey/cn_tools.tar.gz \
        \
        /usbkey/extra/joysetup/

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
        binder_admin_ips
        imgapi_admin_ips
        imgapi_domain
        fwapi_domain
        sapi_domain
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

if setup_state_not_seen "setup_complete"; then
    printf_timer "%-58sdone (%ss)\n" "preparing for setup..."
fi

# Install GZ tools from tarball.
# We use "/opt/smartdc/bin/sdc" to catch the case of a CN being converted to
# an HN: it will have a /opt/smartdc/bin subset already from "cn_tools".
if [[ ! -f /opt/smartdc/bin/sdc ]]; then
    mkdir -p /opt/smartdc &&
        /usr/bin/tar xzof /usbkey/tools.tar.gz -C /opt/smartdc
    printf_timer "%-58sdone (%ss)\n" "installing tools to /opt/smartdc/bin..."
fi

if [[ ! -d /opt/smartdc/sdcadm && -f /usbkey/sdcadm-install.sh ]]; then
    printf_log "%-58s" "installing sdcadm... "
    /usbkey/sdcadm-install.sh || /bin/true
    printf_timer "%4s (%ss)\n" "done"
fi

set_default_fw_rules

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

# Create link for latest platform
create_latest_link


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
        # We'll use IP at first pass, since sapi service is either not
        # running when we create these zones or not yet registered into
        # binder. Then, we'll update at the end of the setup process.
        if [[ "${zone}" == "sapi" || \
              "${zone}" == "binder" || \
              "${zone}" == "assets" ]]; then
          local sapi_url=http://${CONFIG_sapi_admin_ips}
        else
          local sapi_url=http://${CONFIG_sapi_domain}
        fi

        # HEAD-1327 for the first manatee, we want ONE_NODE_WRITE_MODE turned on
        if [[ ${zone} == "manatee" ]]; then
            export ONE_NODE_WRITE_MODE="true"
        fi

        # BASHSTYLED
        ${USB_COPY}/scripts/sdc-deploy.js ${sapi_url} ${zone} ${new_uuid} \
            > ${payload_file}

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

    if [[ ${zone} == "sdc" ]]; then
        # (Re)create the /opt/smartdc/sdc symlink into the sdc zone:
        rm -f /opt/smartdc/sdc || true
        mkdir -p /opt/smartdc &&
        ln -s /zones/${new_uuid}/root/opt/smartdc/sdc /opt/smartdc/sdc
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
    if setup_state_not_seen "sapi_bootstrapped"; then
        echo "Bootstrapping SAPI into SAPI"
        local sapi_uuid
        sapi_uuid=$(vmadm lookup tags.smartdc_role=sapi)
        sapi_adopt vm sapi $sapi_uuid
        zlogin ${sapi_uuid} /usr/bin/bash <<HERE
export ZONE_ROLE=sapi
export ASSETS_IP=${CONFIG_assets_admin_ip}
export CONFIG_AGENT_LOCAL_MANIFESTS_DIRS=/opt/smartdc/\${ZONE_ROLE}
source /opt/smartdc/boot/lib/util.sh
setup_config_agent
upload_values
download_metadata
write_initial_config
registrar_setup
HERE

        setup_state_add "sapi_bootstrapped"
    fi
}

# just run the config-agent in synchronous mode to write initial configs and
# let agents start running before creating core zones
setup_config_agent()
{
    if setup_state_not_seen "config_agent_setup"; then
        AGENTS_DIR=/opt/smartdc/agents

        local prefix=$AGENTS_DIR/lib/node_modules/config-agent
        local tmpfile=/tmp/agent.$$.xml

        mkdir -p $AGENTS_DIR/etc/config-agent.d

        sed -e "s#@@PREFIX@@#${prefix}#g" \
            ${prefix}/smf/manifests/config-agent.xml > ${tmpfile}
        mv ${tmpfile} $AGENTS_DIR/smf/config-agent.xml

        setup_state_add "config_agent_setup"
    fi
}

enable_config_agent()
{
    if setup_state_not_seen "config_agent_enabled"; then
        AGENTS_DIR=/opt/smartdc/agents

        svccfg import $AGENTS_DIR/smf/config-agent.xml
        svcadm enable config-agent

        setup_state_add "config_agent_enabled"
    fi
}

# "sapi_adopt" means adding an "instance" to SAPI
# $1: type
# $2: service_name
# $3: instance_uuid
function sapi_adopt()
{
    local type=$1   # vm or agent
    local service_name=$2
    local uuid=$3
    local sapi_alias=""

    if [[ "${service_name}" == "sapi" ]]; then
      local sapi_url=http://${CONFIG_sapi_admin_ips}
      sapi_alias=$(vmadm get ${uuid} | json alias)
    else
      local sapi_url=http://${CONFIG_sapi_domain}
    fi

    local service_uuid=""
    local sapi_instance=""

    # BEGIN BASHSTYLED
    local i=0
    while [[ -z ${service_uuid} && ${i} -lt 48 ]]; do
        service_uuid=$(curl "${sapi_url}/services?type=${type}&name=${service_name}"\
            -sS -H accept:application/json | json -Ha uuid || true)
        if [[ -z ${service_uuid} ]]; then
            echo "Unable to get service_uuid from sapi yet.  Sleeping..."
            sleep 5
        fi
        i=$((${i} + 1))
    done
    [[ -n ${service_uuid} ]] || \
    fatal "Unable to get service_uuid for role ${service_name} from SAPI"

    i=0
    while [[ -z ${sapi_instance} && ${i} -lt 48 ]]; do
        if [[ -n ${sapi_alias} ]]; then
            sapi_instance=$(curl ${sapi_url}/instances -sS -X POST \
                -H content-type:application/json \
                -d "{ \"service_uuid\" : \"${service_uuid}\", \"uuid\" : \"${uuid}\", \"params\": { \"alias\": \"${sapi_alias}\"} }" \
            | json -H uuid || true)
        else
            sapi_instance=$(curl ${sapi_url}/instances -sS -X POST \
                -H content-type:application/json \
                -d "{ \"service_uuid\" : \"${service_uuid}\", \"uuid\" : \"${uuid}\" }" \
            | json -H uuid || true)
        fi
        if [[ -z ${sapi_instance} ]]; then
            echo "Unable to adopt ${service_name} ${uuid} into sapi yet.  Sleeping..."
            sleep 5
        fi
        i=$((${i} + 1))
    done
    # END BASHSTYLED

    [[ -n ${sapi_instance} ]] || fatal "Unable to adopt ${uuid} into SAPI"
    echo "Adopted service ${service_name} to instance ${uuid}"
}

# For adopting agent instances on SAPI we first generate a UUID and then create
# an instance with that UUID. The instance UUID should written to a place where
# it doesn't get removed on upgrades so agents keep their UUIDs. Also, when
# setting up config-agent we write the instances UUIDs to its config file
function adopt_agents()
{
    if setup_state_not_seen "agents_adopted"; then
        AGENTS_DIR=/opt/smartdc/agents
        CONFIGURABLE_AGENTS="net-agent vm-agent cn-agent \
          agents_core amon-agent amon-relay \
          config-agent firewaller smartlogin \
          cabase cainstsvc hagfish-watcher cmon-agent"

        for agent in $CONFIGURABLE_AGENTS; do
            local instance_uuid
            instance_uuid=$(cat $AGENTS_DIR/etc/$agent)

            if [[ -z ${instance_uuid} ]]; then
                instance_uuid=$(uuid -v4)
                echo $instance_uuid > $AGENTS_DIR/etc/$agent
            fi

            sapi_adopt agent $agent $instance_uuid
        done

        setup_state_add "agents_adopted"
    fi
}

# We guard on 'sdczones_created' to allow restarting a partially complete
# headnode setup. We also guard on 'setup_complete' to allow conversion of CNs
# to secondary headnodes without re-bootstrapping core services.
if setup_state_not_seen "setup_complete" \
        && setup_state_not_seen "sdczones_created"; then

    # Import all the USB key images into the zpool -- in ancestry order.
    cat /usbkey/images/*.imgmanifest \
        | json -e 'this.origin = this.origin || this.uuid' -ga origin uuid \
        | tsort \
        | while read img_uuid; do

        # Checking /zones/$img_uuid is a little faster than using exit
        # status 3 from `imgadm get $img_uuid` to see if the image is already
        # installed in the zpool.
        if [[ ! -d /zones/${img_uuid} ]]; then
            img_namever=$(json -f /usbkey/images/$img_uuid.imgmanifest \
                -a -d@ name version)
            printf_log "%-58s" "importing image ${img_namever:0:37}... "
            imgadm install -m /usbkey/images/$img_uuid.imgmanifest \
                -f /usbkey/images/$img_uuid.imgfile
            printf_timer "done (%ss)\n"
        fi
    done

    # These are here in the order they'll be brought up.
    create_zone assets
    create_zone sapi

    # get SAPI standing up, then use that.
    sdc_init_application
    export USE_SAPI="true"

    create_zone binder

    # Here we bootstrap SAPI to be aware of itself, including writing out
    # its standard DNS config.
    bootstrap_sapi

    # once SAPI is ready we configure the CN config agents before core zones
    adopt_agents
    setup_config_agent

    create_zone manatee
    create_zone moray
    create_zone amonredis
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

    # First we write the agents config in synchronous mode, then we update the
    # config-agent config with SAPI's domain and import the SMF manifest.
    enable_config_agent

    # copy sdc-manatee tools to GZ - see MANATEE-86
    echo "==> Copying manatee tools to GZ."
    manatee=$(vmadm lookup tags.smartdc_role=manatee | tail -1)
    for file in $(ls /zones/${manatee}/root/opt/smartdc/manatee/bin/sdc*); do
        tool=$(basename ${file} .js)
        mv ${file} /opt/smartdc/bin/${tool}
    done

    # Create wrapper for sapiadm into the GZ and execute it from
    # the config agent.

    from_dir=/opt/smartdc/agents/lib/node_modules/config-agent
    to_dir=/opt/smartdc/bin
    rm -f ${to_dir}/sapiadm

    # BEGIN BASHSTYLED
    cat <<EOF > ${to_dir}/sapiadm
#!/bin/bash
exec ${from_dir}/build/node/bin/node ${from_dir}/cmd/sapiadm.js "\$@"
EOF
    # END BASHSTYLED
    chmod +x ${to_dir}/sapiadm

    # Update assets0 zone sapi-url
    vmadm update $(vmadm lookup -1 tags.smartdc_role=assets) <<EOF
{"set_customer_metadata": {"sapi-url": "http://${CONFIG_sapi_domain}"}}
EOF

    setup_state_add "sdczones_created"
fi


# Import all the USB key images into IMGAPI.
function import_smartdc_service_images {
    local img_uuid
    local img_manifest
    local img_file

    # The `tsort` is a "total order" sort to ensure origin images are imported
    # first.
    cat /usbkey/images/*.imgmanifest \
        | json -e 'this.origin = this.origin || this.uuid' -ga origin uuid \
        | tsort \
        | while read img_uuid; do

        img_manifest=/usbkey/images/$img_uuid.imgmanifest
        img_file=/usbkey/images/$img_uuid.imgfile

        # We'll retry up to 3 times on errors reaching IMGAPI.
        local ok=false
        local retries=0
        while [[ ${ok} == "false" && ${retries} -lt 3 ]]; do
            local status
            status=$(/opt/smartdc/bin/sdc-imgapi /images/${img_uuid} \
                | head -1 | awk '{print $2}')
            if [[ "${status}" == "404" ]]; then
                echo "Importing Triton image ${img_uuid} into IMGAPI:"
                echo "    manifest: ${img_manifest}"
                echo "    file:     ${img_file}"

                # Skip the check that "owner" exists in UFDS during setup
                # b/c if this is not the DC with the UFDS master, then the
                # admin user will not have been replicated yet.
                local imgadm_retries=0
                local bail=true
                # We have to retry the sdc-imgadm command here as well.
                while [[ ${imgadm_retries} -lt 6 ]]; do
                    if ! err=$(/opt/smartdc/bin/sdc-imgadm \
                        import --skip-owner-check -m ${img_manifest} \
                        -f ${img_file} 2>&1 | awk '{print $3;}'); then
                            if [[ ${err} == "(ImageUuidAlreadyExists):" ]]; then
                                bail=false
                                break;
                            fi
                            imgadm_retries=$((${retries} + 1))
                    else
                            bail=false
                            break;
                    fi
                done
                if [[ ${bail} == "true" ]]; then
                    fatal "Unable to import image file ${img_file}" \
                        " after ${retries} tries."
                fi
                ok=true
            elif [[ "${status}" == "200" ]]; then
                # exists
                echo "Skipping import of Triton image ${img_uuid}: " \
                    "already in IMGAPI."
                ok=true
            else
                retries=$((${retries} + 1))
            fi
        done
        if [[ ${ok} != "true" ]]; then
            fatal "Unable to import image ${img_uuid} after ${retries} tries."
        fi
    done
}


# 'import_smartdc_service_images' setup state was added after some still-
# supported headnodes were setup, therefore guard on 'setup_complete' as well.
if setup_state_not_seen "import_smartdc_service_images"; then
if setup_state_not_seen "setup_complete"; then
    # Import bootstrapped core images into IMGAPI.
    import_smartdc_service_images
    setup_state_add "import_smartdc_service_images"
fi
fi


#
# Once SDC has finished setup, upgrade SAPI to full mode.  This call
# informs SAPI that its dependent SDC services are ready and that it should
# store the SDC deployment configuration persistently.
#
if setup_state_not_seen "sapi_full_mode"; then
if setup_state_not_seen "setup_complete"; then
    (( i = 0 )) || true
    while :; do
        if /opt/smartdc/bin/sdc-sapi /mode?mode=full -X POST -m 5 --fail; then
            break
        fi
        if (( i++ >= 48 )); then
            fatal "Could not upgrade SAPI to full mode"
        fi
        printf_log "%-58s" "SAPI isn't in full mode yet..."
        sleep 5
    done
    setup_state_add "sapi_full_mode"
fi
fi


if setup_state_not_seen "setup_complete"; then
    # Install all AMON probes, but don't fail setup if it doesn't work
    /opt/smartdc/bin/sdc-amonadm update || /bin/true

    # Run a post-install script. This feature is not formally supported in SDC
    if [ -f ${USB_COPY}/scripts/post-install.sh ]; then
        printf_log "%-58s" "Executing post-install script..."
        bash ${USB_COPY}/scripts/post-install.sh
        printf_log "done\n"
    fi

    printf_timer "%-58sdone (%ss)\n" "completing setup..."

    if [ $restore == 0 ]; then
        echo "" >&${CONSOLE_FD}
        printf_timer "FROM_START" \
"==> Setup complete (in %s seconds). Press [enter] to get login prompt.\n"
        echo "" >&${CONSOLE_FD}
    fi

    setup_state_mark_complete
    rm -f /tmp/.ur-startup
    svcadm restart ur
fi


exit 0
