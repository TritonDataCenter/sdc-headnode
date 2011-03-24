#!/bin/bash
#
# Copyright (c) 2011, Joyent Inc., All rights reserved.
#


ERRORLOG="/tmp/destroy_zone-$1.$$"
exec 5>${ERRORLOG}
BASH_XTRACEFD=5
export PS4='+(${BASH_SOURCE}:${LINENO}): ${SECONDS} ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

set -o errexit
set -o xtrace

zone=$1
if [[ -z ${zone} ]]; then
    echo "Usage: $0 <zone>"
    exit 1
fi

echo -n "Destroying '${zone}':"
zoneadm -z ${zone} halt || /bin/true
echo -n " halt"
zoneadm -z ${zone} uninstall -F || /bin/true
echo -n ", uninstall"
zonecfg -z ${zone} delete -F
echo -n ", delete "

echo " ... DONE!"

exit 0
