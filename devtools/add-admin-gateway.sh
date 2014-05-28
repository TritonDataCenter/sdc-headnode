#!/bin/bash
#
# Copyright (c) 2013 Joyent Inc., All Rights Reserved.
#
# This adds a gateway to VMs on the admin network
#
# WARNINGS:
#
# DO NOT USE IN PRODUCTION.
# DO NOT USE UNLESS YOU NEED IT AND DO NOT WRITE SOFTWARE THAT DEPENDS ON THIS.
#

#export PS4='${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -o xtrace
set -o errexit
set -o pipefail

if [[ "$(uname)" != "SunOS" ]] || [[ "$(uname -v | cut -d'_' -f1)" != "joyent" ]]; then
    echo "FATAL: this only works on the SmartOS Live Image!"
    exit 1
fi

if [[ -z "$1" ]]; then
    echo "usage: $0 <admin gateway to add>"
    exit 1
fi

vmadm_filter="nics.*.nic_tag=admin nics.*.vlan_id=0"
for line in $(vmadm lookup -j ${vmadm_filter} | json -e '
    this.admin_nic = this.nics[0].nic_tag == "admin" ? this.nics[0].mac :
        ((this.nics[1] && this.nics[1].nic_tag == "admin") ? this.nics[1].mac :
        "-");' -a uuid admin_nic brand -d '='); do
    fields=(${line//=/ })
    uuid=${fields[0]}
    mac=${fields[1]}
    brand=${fields[2]}

    if [[ ${brand} == "kvm" ]] || [[ ${mac} == "-" ]]; then
        echo "Skipping VM ${uuid} (admin mac=${mac}, brand=${brand})"
        continue
    fi

    echo "Updating VM ${uuid}, nic: ${mac}"
    vmadm update ${uuid} <<EOF
    {
        "update_nics": [
            {
                "mac": "${mac}",
                "gateway": "$1"
            }
        ]
    }
EOF
    zlogin ${uuid} /usr/sbin/route add default $1 || /bin/true
done

exit 0
