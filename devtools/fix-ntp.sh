#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

if [[ -z ${NTP_SERVER} ]]; then
    NTP_SERVER=$(grep "server " /etc/inet/ntp.conf  | head -1 | cut -d ' ' -f2)
fi

svcadm disable ntp \
    ; ntpdate ${NTP_SERVER} \
    && svcadm enable ntp

exit 0
