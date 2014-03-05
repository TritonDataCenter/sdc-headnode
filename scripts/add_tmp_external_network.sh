#!/usr/bin/bash
#
# Copyright (c) 2014, Joyent, Inc. All rights reserved.
#
# add_tmp_external_network.sh sets up access to the external world before the
# host has gone through configuration.
#

function fatal {
    echo "$0: fatal error: $*"
    exit 1
}

ping 8.8.8.8
[ $? -ne 0 ] || fatal "Host already has external access"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <answers.json location> <external vlan id>"
    exit 1
fi

if [ ! -e "$1" ]; then
    echo "$1 does not exist"
    exit 1
fi

JSON=$(cat $1 | json)
[ $? -eq 0 ] || fatal "$1 isn't valid json"
VLAN=$2
EXTERNAL_NIC=$(echo "$JSON" | json external_nic)
: ${EXTERNAL_NIC?:"$0 doesn't contain an external_nic property"}
EXTERNAL_INTERFACE=$(dladm show-phys -m | grep "$EXTERNAL_NIC" | cut -d ' ' -f 1)
: ${EXTERNAL_INTERFACE?:"Unable to find external interface for $EXTERNAL_NIC"}
EXTERNAL_IP=$(echo "$JSON" | json external_ip)
: ${EXTERNAL_IP?:"$0 doesn't contain an external_ip property"}
EXTERNAL_GATEWAY=$(echo "$JSON" | json external_gateway)
: ${EXTERNAL_GATEWAY?:"$0 doesn't contain an external_gateway property"}

dladm create-vnic -l $EXTERNAL_INTERFACE -v $VLAN temp0
[ $? -eq 0 ] || fatal "Unable to create vnic"
ifconfig temp0 plumb
[ $? -eq 0 ] || fatal "Unable to plumb interface"
ifconfig temp0 $EXTERNAL_IP netmask 255.255.255.0 up
[ $? -eq 0 ] || fatal "Unable bring interface up"
route add default $EXTERNAL_GATEWAY
[ $? -eq 0 ] || fatal "Unable to add default route"
echo 'Done.'
