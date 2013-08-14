#!/usr/bin/bash
#
# get-latest.sh: produces a list of the latest images

# set -o errexit
# set -o xtrace

ROLES="adminui amon amonredis ca cloudapi cnapi dapi dhcpd fwapi imgapi napi sapi ufds usageapi vmapi workflow"

function print_latest
{
    local ROLE=$1
    local IMAGE=$2

    echo "export ${ROLE^^}_IMAGE=${IMAGE%% *}"
}

for ROLE in $ROLES; do
    print_latest $ROLE "$(updates-imgadm list version=~master name=$ROLE | tail -1)"
done
