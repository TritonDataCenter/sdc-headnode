#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

PATH=/usr/bin:/usr/sbin
export PATH

if [[ $# != 2 ]]; then
    echo "Usage: $0 <zone_name> <target_directory>"
    exit 1
fi

ROLE=cloudapi
UUID=$1
TARGET_DIR=$2
CFG_FILE=/zones/${UUID}/root/opt/smartdc/cloudapi/etc/cloudapi.cfg
PLUG_DIR=/zones/${UUID}/root/opt/smartdc/cloudapi/plugins
SSL_DIR=/zones/${UUID}/root/opt/smartdc/cloudapi/ssl

if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "Invalid directory: '${TARGET_DIR}'"
    exit 1
fi

# Create the backup directory:
mkdir -p ${TARGET_DIR}/${ROLE}

echo "==> Saving config file for zone '${ZONE}'"
[ -f $CFG_FILE ] && cp $CFG_FILE ${TARGET_DIR}/${ROLE}

if [ -d $PLUG_DIR ]; then
    echo "==> Saving plugins for zone '${ROLE}'"
    mkdir -p ${TARGET_DIR}/${ROLE}/plugins
    (cd ${PLUG_DIR} && cp -pr * ${TARGET_DIR}/${ROLE}/plugins)
fi

if [ -d $SSL_DIR ]; then
    echo "==> Saving SSL certs for zone '${ROLE}'"
    mkdir -p ${TARGET_DIR}/${ROLE}/ssl
    (cd ${SSL_DIR} && cp -p * ${TARGET_DIR}/${ROLE}/ssl)
fi

exit 0
