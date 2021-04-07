#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Copyright 2021 Joyent, Inc.

# This script will take a metadata file provided as a boot module from
# Equinix Tinkerbell (e.g., Equinix Metal) and generate a suitable answers.json
# file. If the metadata is provided as a bood module, prompt-config.sh will
# call this script and then use the generated answers file for unattended
# install.

# The metadata file gets passed in on the command line by prompt-config.sh
md="$1"

# shellcheck disable=2154
if [[ -n "$TRACE" ]]; then
    # BASHSTYLED
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

if ! [[ -f $md ]]; then
    printf 'No tinkerbell metadata\n'
    exit
fi

# This is a short hand sanity test to make sure the metadata file is valid
# JSON, and likely actually came from tinkerbell.
if ! json -f "$md" iqn | grep -q iqn ; then
    printf 'Metadata file is not valid\n' >&2
    exit 1
fi

# Number of IPs by prefix-length
# num_ips[24] == 256
num_ips=(
    4294967296
    2147483648
    1073741824
    536870912
    268435456
    134217728
    67108864
    33554432
    16777216
    8388608
    4194304
    2097152
    1048576
    524288
    262144
    131072
    65536
    32768
    16384
    8192
    4096
    2048
    1024
    512
    256
    128
    64
    32
    16
    8
    4
    2
    1
)

# Return a value or default if it doesn't exist
function get_default {
    local val
    val=$(get_value "$1")
    if (( ${#val} < 1 )); then
        echo "$2"
        return
    fi
    echo "$val"
}

function get_value {
    json -f "$md" "$@"
}

function random_octet {
    echo $(( RANDOM % 255))
}

# These will always be present
datacenter_name="$(get_value facility)"
admin_nic="$(get_value network.interfaces.1.mac)"
external_nic="$(get_value network.interfaces.0.mac)"
addresses="$(get_value network.addresses)"

# Derived values
IFS=: read -a a_mac <<< "$admin_nic"
admin_net=$(printf '10.%d.%d' "0x${a_mac[4]}" "0x${a_mac[5]}")

admin_ip="${admin_net}.10"
admin_provisionable_start="${admin_net}.11"

external_net=$(json -a -c 'this.public===true' <<< "$addresses")
external_ip=$(json address <<< "$external_net")
external_net_address=$(json parent_block.network <<< "$external_net")
external_netmask=$(json parent_block.netmask <<< "$external_net")
external_prefix_len=$(json parent_block.cidr <<< "$external_net")
external_gateway=$(json gateway <<< "$external_net")

IFS=. read -a e_addr <<< "$external_net_address"
external_provisionable_start=$( printf '%d.%d.%d.%d' \
    "${e_addr[0]}" "${e_addr[1]}" "${e_addr[2]}" "$(( ${e_addr[3]} + 3))")
external_provisionable_end=$( printf '%d.%d.%d.%d' \
    "${e_addr[0]}" "${e_addr[1]}" "${e_addr[2]}" \
    "$(( ${e_addr[3]} + ${num_ips[${external_prefix_len}]} - 2))")

# Optional values
company_name="$(get_default customdata.datacenter_company_name none)"
dc_prefix=$(tr -d '1234567890' <<< "$datacenter_name")
region_name=$(get_default customdata.region_name "$dc_prefix")
datacenter_location=$(get_default customdata.datacenter_location none)
dns_domain=$(get_default customdata.dns_domain triton.local)
dns_search="$dns_domain"
mail_to=$(get_default customdata.mail_to "admin@${dns_domain}")
mail_from=$(get_default customdata.mail_from "$mail_to")
dns_resolver1=$(get_default customdata.dns_resolver1 8.8.8.8)
dns_resolver2=$(get_default customdata.dns_resolver1 8.8.4.4)
update_channel=$(get_default customdata.update_channel release)
ntp_servers=$(get_default customdata.ntp_servers 0.smartos.pool.ntp.org)

# Generate random passwords equivalent to 128 bit keys
root_passwd=$(get_default customdata.root_password "$(openssl rand -hex 16)")
admin_passwd=$(get_default customdata.admin_password "$(openssl rand -hex 16)")

## Output answers.json

cat << EOF
{
    "config_console": "serial",
    "skip_instructions": true,
    "simple_headers": false,
    "skip_final_confirm": true,
    "skip_edit_config": true,
    "datacenter_company_name": "$company_name",
    "region_name": "$region_name",
    "datacenter_name": "$datacenter_name",
    "datacenter_location": "$datacenter_location",
    "admin_nic": "$admin_nic",
    "admin_ip": "$admin_ip",
    "admin_provisionable_start": "$admin_provisionable_start",
    "setup_external_network": true,
    "external_nic": "$external_nic",
    "external_ip": "$external_ip",
    "external_vlan_id": "0",
    "external_provisionable_start": "$external_provisionable_start",
    "external_provisionable_end": "$external_provisionable_end",
    "external_netmask": "$external_netmask",
    "external_gateway": "$external_gateway",
    "headnode_default_gateway": "<default>",
    "dns_resolver1": "$dns_resolver1",
    "dns_resolver2": "$dns_resolver2",
    "dns_domain": "$dns_domain",
    "dns_search": "$dns_search",
    "dhcp_range_end": "<default>",
    "ntp_host": "$ntp_servers",
    "root_password": "$root_passwd",
    "admin_password": "$admin_passwd",
    "mail_to": "$mail_to",
    "mail_from": "$mail_from",
    "phonehome_automatic": "false",
    "update_channel": "$update_channel"
}
EOF
