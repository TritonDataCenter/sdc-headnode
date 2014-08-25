#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Generate a changelog between two given platform date strings.
#
# Assumptions:
# - assume the platform builds are from the "master" branch
# - assumes the builds are still on /Joyent_Dev/stor/builds/platform
#
# Usage:
#       ./changelog-platform.sh <src> <dst>
#
# Example:
#       ./changelog-platform.sh 20140314T221527Z 20140324T202823Z
#


if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


#---- globals

TOP=$(cd $(dirname $0)/; pwd)

# Repos from the "platform" key in mountain-gorilla.git/targets.json.
repo_url_from_var=$(cat <<EOM
{
    "SMARTOS_LIVE_SHA": {"name": "smartos-live", "url": "git@github.com:joyent/smartos-live.git"},
    "ILLUMOS_JOYENT_SHA": {"name": "illumos-joyent", "url": "git@github.com:joyent/illumos-joyent.git"},
    "ILLUMOS_EXTRA_SHA": {"name": "illumos-extra", "url": "git@github.com:joyent/illumos-extra.git"},
    "ILLUMOS_KVM_SHA": {"name": "illumos-kvm", "url": "git@github.com:joyent/illumos-kvm.git"},
    "ILLUMOS_KVM_CMD_SHA": {"name": "illumos-kvm-cmd", "url": "git@github.com:joyent/illumos-kvm-cmd.git"},
    "UR_AGENT_SHA": {"name": "ur-agent", "url": "git@git.joyent.com:ur-agent.git"},
    "SDC_PLATFORM_SHA": {"name": "sdc-platform", "url": "git@git.joyent.com:sdc-platform.git"},
    "MDATA_CLIENT_SHA": {"name": "mdata-client", "url": "git@github.com:joyent/mdata-client.git"}
}
EOM)


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}



#---- mainline

src_date=$1
dst_date=$2
[[ -n "$src_date" ]] || fatal "<src_date> was not given"
[[ -n "$dst_date" ]] || fatal "<dst_date> was not given"

echo "# SDC Platform $src_date..$dst_date"
echo ""

src_config_mk=$(mget /Joyent_Dev/stor/builds/platform/master-$src_date/config.mk | grep '_SHA=')
dst_config_mk=$(mget /Joyent_Dev/stor/builds/platform/master-$dst_date/config.mk | grep '_SHA=')


echo "$repo_url_from_var" | json --keys -a | while read key; do
    repo_url=$(echo "$repo_url_from_var" | json $key.url)
    repo_name=$(echo "$repo_url_from_var" | json $key.name)
    src_sha=$(echo "$src_config_mk" | grep $key | cut -d= -f2)
    dst_sha=$(echo "$dst_config_mk" | grep $key | cut -d= -f2)
    echo "## $repo_name"
    echo ""
    if [[ -z "$src_sha" ]]; then
        echo "error: could not find '$key' in /Joyent_Dev/stor/builds/platform/master-$src_date/config.mk"
    elif [[ -z "$dst_sha" ]]; then
        echo "error: could not find '$key' in /Joyent_Dev/stor/builds/platform/master-$dst_date/config.mk"
    elif [[ "$src_sha" == "$dst_sha" ]]; then
        echo "(no changes, $repo_url#$src_sha)"
    else
        echo "$repo_url#$src_sha..$dst_sha"
        echo ""
        repo_dir=$TOP/tmp/$repo_name
        if [[ -d $repo_dir ]]; then
            echo "  * git pull $repo_url" >&2
            (cd $repo_dir && git pull >/dev/null)
        else
            echo "  * git clone $repo_url" >&2
            mkdir -p $(dirname $repo_dir)
            rm -rf $repo_dir.tmp
            git clone $repo_url $repo_dir.tmp >/dev/null
            mv $repo_dir.tmp $repo_dir
        fi
        echo '```'
        # Compact git log, drop the timezone info for brevity.
        (cd $repo_dir && \
            git log --pretty=format:'[%ci] %h -%d %s <%an>' $src_sha..$dst_sha \
            | sed -E 's/ [-+][0-9]{4}\]/]/')
        echo '```'
        # TODO: get full log, extract list of tickets and show ticket info
    fi
    echo ""
    echo ""
done

