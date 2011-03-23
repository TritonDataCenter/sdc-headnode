#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#


export PS4='+(${BASH_SOURCE}:${LINENO}): ${SECONDS} ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o errexit
set -o xtrace

TEMPDIR="/var/tmp/build-upgrade.$$"
AGENTS_BASE="https://guest:GrojhykMid@216.57.203.66:444/coal/live_147/agents"
RUBYAPP_BASE="https://joydev:leichiB8eeQu@216.57.203.66/release"

AGENTS=( \
    atropos/develop/atropos-develop-* \
    cloud_analytics/master/cabase-master-* \
    cloud_analytics/master/cainstsvc-master-* \
    dataset_manager/develop/dataset_manager-develop-* \
    heartbeater/develop/heartbeater-develop-* \
    provisioner/develop/provisioner-develop-* \
    zonetracker/develop/zonetracker-develop-* \
)

RUBYAPP_ZONES=( \
    adminui \
    capi \
    dnsapi \
    mapi \
    pubapi \
)

function get_latest_agent
{
    url=$1
    pattern=$2
    out_dir=$3

    latest=$(curl -k -sS ${url}/ \
                 | grep "href=\"${pattern}" \
                 | cut -d'"' -f2 | sort | tail -1)

    oldwd=$(pwd)
    cd ${out_dir}
    curl -k --progress -O ${url}/${latest}
    cd ${oldwd}
    echo "==> downloaded ${latest}"
}

function get_agents
{
    for agent in "${AGENTS[@]}"; do
        url="${AGENTS_BASE}/$(dirname ${agent})"
        pattern=$(basename ${agent})
        get_latest_agent "${url}" "${pattern}" "${TEMPDIR}/upgrade/agents"
    done
}

# XXX this function copied from usb-headnode/bin/build-image

#
# RETURNS (via echo):
#
# The value considered newer between a and b
# If values are same: a
#
function newer_of
{
    a=$1
    b=$2

    if [[ -z ${b} ]]; then
        fatal "is_newer() usage: is_newer \$a \$b"
    fi

    if [[ -z ${a} ]]; then
        echo "${b}" # newer since we have b but not a!
        return 0
    fi

    # Strip off .tar.bz2 extension (if has one)
    # break into elements separated by - _ or .
    a_array=(`echo "${a}" \
        | sed -e "s/\.tar\.bz2$//" \
        | sed -e "s/[-_.]/ /g" | tr -s ' '`)
    b_array=(`echo "${b}" \
        | sed -e "s/\.tar\.bz2$//" \
        | sed -e "s/[-_.]/ /g" | tr -s ' '`)

    idx=0
    while [[ -n ${a_array[${idx}]} || -n ${b_array[${idx}]} ]]; do
        a_val=${a_array[${idx}]}
        b_val=${b_array[${idx}]}

        #echo "a[${a_val}] vs b[${b_val}]" >&2

        # if one is empty at this idx, return the other
        if [[ -z ${a_val} ]]; then
            echo "${b}"
            return 0
        fi
        if [[ -z ${b_val} ]]; then
            echo "${a}"
            return 0
        fi

        if [[ ${a_val} == ${b_val} ]]; then
            # same, so do nothing this loop
            true
        elif [[ ${a_val} =~ ^[0-9]+$ && ${b_val} =~ ^[0-9]+$ ]]; then
            # all digits (sort numerically)
            if [[ ${b_val} -gt ${a_val} ]]; then
                echo "${b}"
            else
                echo "${a}"
            fi
            return 0
        else
            # not all digits (sort lexicographically)
            if [[ ${b_val} > ${a_val} ]]; then
                echo "${b}"
            else
                echo "${a}"
            fi
            return 0
        fi

        idx=$((${idx} + 1))
    done
    #echo "COMPARING: '${a}' vs '${b}'" >&2

    echo "${a}"
    return 0
}

function get_latest_zone
{
    url=$1
    pattern=$2
    out_dir=$3

    latest=
    for file in $(curl -k -sS ${url}/ \
        | grep "href=" \
        | cut -d'"' -f2 \
        | grep "${pattern}"); do

        #echo "LATEST BEF: ${latest}"
        latest=$(newer_of "${latest}" "${file}")
        #echo "LATEST NOW: ${latest}"
    done
    [[ $? -ne 0 || -z ${latest} ]] \
        && fatal "Error getting file list for ${pattern}"

    oldwd=$(pwd)
    cd ${out_dir}
    curl -k --progress -O ${url}/${latest}
    cd ${oldwd}
    echo "==> downloaded ${latest}"
}

function get_zones
{
    for zone in "${RUBYAPP_ZONES[@]}"; do
        get_latest_zone "${RUBYAPP_BASE}" "${zone}-*" "${TEMPDIR}/upgrade/zones"
    done
}

function cleanup
{
    rm -rf ${TEMPDIR}
}

rm -rf ${TEMPDIR}
trap cleanup EXIT
mkdir -p ${TEMPDIR}/upgrade
mkdir -p ${TEMPDIR}/upgrade/agents
mkdir -p ${TEMPDIR}/upgrade/usbkey
mkdir -p ${TEMPDIR}/upgrade/zones

get_agents
get_zones

(cd ${TEMPDIR} && tar -cvf - upgrade) | gzip -c > upgrade.tgz

exit 0
