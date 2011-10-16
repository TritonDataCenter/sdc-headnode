#!/bin/bash

if [[ -z ${NTP_SERVER} ]]; then
    NTP_SERVER=$(grep "server " /etc/inet/ntp.conf  | head -1 | cut -d ' ' -f2)
fi

svcadm disable ntp \
    ; ntpdate ${NTP_SERVER} \
    && svcadm enable ntp

exit 0
