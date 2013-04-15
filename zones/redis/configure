#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

svccfg import /var/tmp/redis.smf

# XXX Huh?  Shouldn't `svcadm restart redis` be sufficient?  Either way, why are
# we doing this?
svcadm disable redis
svcadm enable redis

exit 0
