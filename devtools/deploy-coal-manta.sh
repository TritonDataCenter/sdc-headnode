#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

set -e
set -x

# Install the Manta "management" zone
/usbkey/scripts/setup_manta_zone.sh
MANTA=$(vmadm lookup alias=manta0)

# Set up the extra manta and manta-nat networks
if [[ ! -f /var/tmp/networking/coal.json ]]; then
    ln -s /zones/$MANTA/root/opt/smartdc/manta-deployment/networking /var/tmp/networking
    cd /var/tmp/networking
    ./gen-coal.sh > coal.json
    ./manta-net.sh ./coal.json
    cd -
fi

# Now deploy...
cat /opt/smartdc/agents/lib/node_modules/marlin/etc/agentconfig.coal.json | json -e 'this.zoneDefaultImage="1.6.3"' > /tmp/.agent.json
mv /tmp/.agent.json /opt/smartdc/agents/lib/node_modules/marlin/etc/agentconfig.coal.json
zlogin $MANTA "bash -l -c \"/opt/smartdc/manta-deployment/bin/manta-init -e nobody@joyent.com -s coal -r coal -m fd2cc906-8938-11e3-beab-4359c665ac99\""
zlogin $MANTA "bash -l -c \"/opt/smartdc/manta-deployment/bin/manta-deploy-coal\""
