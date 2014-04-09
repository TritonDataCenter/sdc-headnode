#!/usr/bin/bash
#
# Copyright (c) 2014, Joyent, Inc. All rights reserved.
#



LOG_FILENAME=/tmp/manatee-v2-upgrade.$$.log
exec 4>${LOG_FILENAME}
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
PATH=/opt/smartdc/bin:/usr/sbin:/usr/bin:$PATH

set -o errexit
set -o xtrace
set -o pipefail

function fatal
{
    echo "FATAL: $*" >&2
    exit 2
}

function usage
{
    cat >&2 <<EOF
Usage: $0 <image_uuid>
EOF
    exit 1
}

# params
image_uuid=$1
if [[ -z ${image_uuid} ]]; then
    usage
fi

function create_tarball
{
    tarball=/tmp/manatee-v2-upgrade.tgz
    if [[ -f ${tarball} ]]; then
        rm ${tarball}
    fi
    local image_uuid=$1
    local source_path=/zones/${image_uuid}/root/opt/smartdc/manatee
    pushd ${source_path}
    tar zcf ${tarball} .
    popd
}

local_manatee=$(vmadm lookup state=running tags.smartdc_role=manatee | tail -1)

function manatee_stat
{
    # manatee-stat exists in different places depending on the manatee version,
    # and therefore on the stage of the upgrade; find it explicitly.
    local m_stat=
    local result=
    if [[ -f /zones/${local_manatee}/root/opt/smartdc/manatee/bin/manatee-stat ]]; then
        m_stat="/opt/smartdc/manatee/bin/manatee-stat -p \$ZK_IPS"
    elif [[ -f /zones/${local_manatee}/root/opt/smartdc/manatee/node_modules/manatee/bin/manatee-stat ]]; then
        m_stat="/opt/smartdc/manatee/node_modules/manatee/bin/manatee-stat -p \$ZK_IPS"
    else
        fatal "Can't find manatee-stat."
    fi
    if [[ ! -f /zones/${local_manatee}/root/opt/smartdc/etc/zk_ips.sh ]]; then
        # race condition on the creation of zk_ips when the local manatee
        # is reprovisioning/rebooting.
        result="{}"
    else
        result=$(zlogin ${local_manatee} "source /opt/smartdc/etc/zk_ips.sh; ${m_stat}");
    fi
    echo ${result}
}

function wait_for_manatee
{
    local expect=$1
    local result=
    local count=0
    echo "Waiting for manatee to reach ${expect}"
    while [[ ${result} != ${expect} ]]; do
        result=$(manatee_stat | json -e '
            if (!this.sdc) {
                this.mode = "transition";
            } else if (Object.keys(this.sdc).length===0) {
                this.mode = "empty";
            } else if (this.sdc.primary && this.sdc.sync && this.sdc.async) {
                var up = this.sdc.async.repl && !this.sdc.async.repl.length && Object.keys(this.sdc.async.repl).length === 0;
                if (up && this.sdc.sync.repl && this.sdc.sync.repl.sync_state == "async") {
                    this.mode = "async";
                }
            } else if (this.sdc.primary && this.sdc.sync) {
                var up = this.sdc.sync.repl && !this.sdc.sync.repl.length && Object.keys(this.sdc.sync.repl).length === 0;
                if (up && this.sdc.primary.repl && this.sdc.primary.repl.sync_state == "sync") {
                    this.mode = "sync";
                }
            } else if (this.sdc.primary) {
                var up = this.sdc.primary.repl && !this.sdc.primary.repl.length && Object.keys(this.sdc.primary.repl).length === 0;
                if (up) {
                    this.mode = "primary";
                }
            }

            if (!this.mode) {
                this.mode = "transition";
            }' mode)
        if [[ ${result} == ${expect} ]]; then
            continue;
        elif [[ ${count} -gt 60 ]]; then
            fatal "Timeout (300s) waiting for manatee to reach ${target}"
        else
            count=$((${count} + 1))
            sleep 5
        fi
    done
}

function find_manatees
{
    primary_manatee=$(manatee_stat | json -Ha sdc.primary.zoneId)
    if [[ -z ${primary_manatee} ]]; then
        echo ""
        fatal "Can't find primary manatee"
    fi
    primary_server=$(sdc-vmapi /vms/${primary_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${primary_server} ]]; then
        echo ""
        fatal "Can't find server for primary: ${primary_manatee}"
    fi
    sync_manatee=$(manatee_stat | json -Ha sdc.sync.zoneId)
    if [[ -z ${sync_manatee} ]]; then
        echo ""
        fatal "Can't find sync manatee"
    fi
    sync_server=$(sdc-vmapi /vms/${sync_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${sync_server} ]]; then
        echo ""
        fatal "Can't find server for sync: ${sync_manatee}"
    fi
    async_manatee=$(manatee_stat | json -Ha sdc.async.zoneId)
    if [[ -z ${async_manatee} ]]; then
        echo ""
        fatal "Can't find async manatee"
    fi
    async_server=$(sdc-vmapi /vms/${async_manatee} | json -Ha server_uuid)
    if [[ $? != 0 || -z ${async_server} ]]; then
        echo ""
        fatal "Can't find server for async: ${async_manatee}"
    fi
}

function disable_manatee
{
    local server=$1
    local zone=$2
    echo "Disabling manatee services in ${zone}"
    sdc-oneachnode -n ${server} \
    "svcadm -z ${zone} disable -s manatee-sitter;\
     svcadm -z ${zone} disable -s manatee-snapshotter;\
     svcadm -z ${zone} disable -s manatee-backupserver;"
    if [[ $? != 0 ]]; then
        echo ""
        fatal "Couldn't disable manatee services in ${zone}"
    fi
}

function reprovision_manatee
{
    local server=$1
    local instance=$2
    local current_image=$(sdc-vmapi /vms/${instance} -f | json image_uuid)

    if [[ ${current_image} == ${image_uuid} ]]; then
        echo "Manatee ${zone} already at image ${image_uuid}, skipping."
    else
        echo "Reprovisioning ${instance} to ${image_uuid}..."
        sdc-oneachnode -n ${server} \
            "imgadm import ${image_uuid}"
        sdc-oneachnode -n ${server} \
            "echo '{}' | json -e \"this.image_uuid='${image_uuid}'\" \
            | vmadm reprovision ${instance}"
    fi
}

# mainline

echo "!! log file is ${LOG_FILENAME}"

./download-image.sh ${image_uuid}

echo "Creating upgrade tarball."
create_tarball ${image_uuid}

find_manatees

echo "*** manatee upgrade initial state:"
echo "  current primary: ${primary_manatee} on ${primary_server}"
echo "     current sync: ${sync_manatee} on ${sync_server}"
echo "    current async: ${async_manatee} on ${async_server}"

echo "Disabling async ${async_manatee}"
disable_manatee ${async_server} ${async_manatee}
wait_for_manatee sync

echo "Disabling sync ${sync_manatee}"
disable_manatee ${sync_server} ${sync_manatee}
wait_for_manatee primary

echo "(1/5) Upgrading primary manatee in place"
echo "      ${primary_manatee} on ${primary_server}"
./manatee-v2-in-situ-upgrade.sh ${primary_server} ${primary_manatee} ${tarball}

echo "(2/5) Upgrading sync manatee in place"
echo "      ${sync_manatee} on ${sync_server}"
./manatee-v2-in-situ-upgrade.sh ${sync_server} ${sync_manatee} ${tarball}

# reprovision async
echo "(3/5) Reprovisioning async manatee"
echo "      ${async_manatee} on ${async_server}"
disable_manatee ${async_server} ${async_manatee}
wait_for_manatee sync
reprovision_manatee ${async_server} ${async_manatee} ${image_uuid}
wait_for_manatee async

echo "(4/5) Reprovisioning sync manatee"
echo "      ${sync_manatee} on ${sync_server}"
disable_manatee ${sync_server} ${sync_manatee}
wait_for_manatee sync
reprovision_manatee ${sync_server} ${sync_manatee} ${image_uuid}
wait_for_manatee async

echo "(5/5) Reprovisioning (previously) primary manatee"
echo "      ${primary_manatee} on ${primary_server}"
disable_manatee ${primary_server} ${primary_manatee}
wait_for_manatee sync
reprovision_manatee ${primary_server} ${primary_manatee} ${image_uuid}
wait_for_manatee async

echo "Upgrade complete."

