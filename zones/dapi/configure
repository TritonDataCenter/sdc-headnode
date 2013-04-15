#!/usr/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

PATH=/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin

echo "Updating SMF manifest"
$(/opt/local/bin/gsed -i"" -e "s/@@PREFIX@@/\/opt\/smartdc\/dapi/g" /opt/smartdc/dapi/smf/manifests/dapi.xml)

echo "Importing dapi.xml"
/usr/sbin/svccfg import /opt/smartdc/dapi/smf/manifests/dapi.xml

exit 0
