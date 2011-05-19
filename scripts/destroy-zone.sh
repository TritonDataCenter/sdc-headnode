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

state=`zoneadm -z ${zone} list -p | cut -d: -f3`
while [ "$state" != "installed" ]; do
	sleep 5
	state=`zoneadm -z ${zone} list -p | cut -d: -f3`
	if [ "$state" != "installed" ]; then
		echo
		echo "Waiting for zone to shutdown, state: $state"

		for i in `mount -p | nawk -v zname=${zone} '{
			if (index($3, zname) != 0)
				print $3
		}'`; do
			echo "check file system: $i"
			fuser $i
		done
	fi
done

echo -n " halt"
zoneadm -z ${zone} uninstall -F || /bin/true
echo -n ", uninstall"
zonecfg -z ${zone} delete -F
echo -n ", delete "

echo " ... DONE!"

exit 0
