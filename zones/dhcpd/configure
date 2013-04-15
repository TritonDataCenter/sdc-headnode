#!/bin/bash
#
# Copyright (c) 2012 Joyent Inc., All rights reserved.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

echo "Importing dhcpd manifest"
/usr/sbin/svccfg import /opt/smartdc/booter/smf/manifests/dhcpd.xml

echo "Enabling dhcpd service"
/usr/sbin/svcadm enable smartdc/site/dhcpd

echo "Importing tftpd manifest"
/usr/sbin/svccfg import /opt/smartdc/booter/smf/manifests/tftpd.xml

echo "Enabling tftpd service"
/usr/sbin/svcadm enable network/tftpd

exit 0
