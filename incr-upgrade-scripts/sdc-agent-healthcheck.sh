#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

. /lib/sdc/config.sh

load_sdc_config

export AMQP_HOST=$CONFIG_rabbitmq_domain

overall=0

while read rec
do
    eval $(echo "$rec" | awk  '{ printf("uuid=%s\nsetup=%s\nversion=%s", $1, $2, $3); }')

    if [ "$setup" == "true" ]; then
        if [ "$version" == "" ]; then
            agents="provisioner-v2 zonetracker-v2 ur heartbeat"
        else
            agents="provisioner zonetracker ur heartbeat"
        fi
    else
        agents="ur"
    fi

    for agent in $agents; do
        echo -n "$uuid $agent "

        ping-agent $uuid  $agent timeout=10000 2>&1 | egrep -s "req_id:"

        if [ $? -eq '0' ]; then
            status=ok
        else
            status=error
            overall=1
        fi

        echo "$status"
    done
done < <(sdc-cnapi "/servers?extras=sysinfo" | json -Hga uuid setup sysinfo."SDC Version")

exit $overall