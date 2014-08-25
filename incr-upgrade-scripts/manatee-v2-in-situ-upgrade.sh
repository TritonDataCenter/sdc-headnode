#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

LOG_FILENAME=/tmp/manatee-v2-in-situ-upgrade.$$.log
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
Usage: $0 <server_uuid> <instance_uuid> <tarball_path>
EOF
    exit 1
}
# params

echo "!! log file is ${LOG_FILENAME}"

manatee_server=$1
if [[ -z ${manatee_server} ]]; then
    usage
fi

manatee_instance=$2
if [[ -z ${manatee_instance} ]]; then
    usage
fi

tarball=$3
if [[ -z ${tarball} || ! -f ${tarball} ]]; then
    usage
fi

script=$(dirname $0)/manatee-v2-remote-upgrade.sh
if [[ ! -f ${script} ]]; then
    fatal "Can't find ${script}"
fi

function upload_upgrade
{
    local upgrade_path=$1

    sdc-oneachnode -n ${manatee_server} "mkdir -p ${upgrade_path}"
    sdc-oneachnode -n ${manatee_server} -g ${tarball} -d ${upgrade_path}
    sdc-oneachnode -n ${manatee_server} -g ${script} -d ${upgrade_path}
}

function run_script
{
    local upgrade_path=$1
    local tarball_path=${upgrade_path}/$(basename ${tarball})
    sdc-oneachnode -T 300 -n ${manatee_server} "bash ${upgrade_path}/manatee-v2-remote-upgrade.sh ${manatee_instance} ${tarball_path}"
}

# mainline

upload_upgrade /var/tmp/manatee-upgrade.$$
run_script /var/tmp/manatee-upgrade.$$
