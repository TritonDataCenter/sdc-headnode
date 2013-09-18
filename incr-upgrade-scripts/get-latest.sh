#!/usr/bin/bash
#
# get-latest.sh: produces a list of the latest images

# set -o errexit
# set -o xtrace

ROLES="adminui amon amonredis assets ca cloudapi cnapi dapi dhcpd fwapi imgapi keyapi napi papi rabbitmq redis sapi sdc sdcsso ufds usageapi vmapi workflow"

function print_latest
{
    local ROLE=$1
    local IMAGE=$2

    echo "export ${ROLE^^}_IMAGE=${IMAGE%% *}"
}

for ROLE in $ROLES; do
    print_latest $ROLE "$(updates-imgadm list version=~master name=$ROLE | tail -1)"
done

# manta-nameservice == binder
echo "export BINDER_IMAGE=$(updates-imgadm list version=~master name=manta-nameservice | tail -1 | cut -d ' ' -f1)"
# manta-postgres == manatee
echo "export MANATEE_IMAGE=$(updates-imgadm list version=~master name=manta-postgres | tail -1 | cut -d ' ' -f1)"
# manta-deployment == manta
echo "export MANTA_IMAGE=$(updates-imgadm list version=~master name=manta-deployment | tail -1 | cut -d ' ' -f1)"
# manta-moray == moray
echo "export MORAY_IMAGE=$(updates-imgadm list version=~master name=manta-moray | tail -1 | cut -d ' ' -f1)"
