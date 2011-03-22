#!/bin/bash
#
# Copyright (c) 2011, Joyent Inc., All rights reserved.
#

set -o errexit

zone=$1
if [[ -z ${zone} ]]; then
    echo "Usage: $0 <zone>"
    exit 1
fi

echo -n "Destroying '${zone}':"
zoneadm -z ${zone} halt
echo -n " halt"
zoneadm -z ${zone} uninstall -F
echo -n ", uninstall"
zonecfg -z ${zone} delete -F
echo -n ", delete "

echo " ... DONE!"

exit 0
