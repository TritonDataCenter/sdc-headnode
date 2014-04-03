#!/bin/bash

set -e
set -x

# Install the Manta "management" zone
/usbkey/scripts/setup_manta_zone.sh
MANTA=$(vmadm lookup alias=manta0)

# Set up the extra manta and manta-nat networks
ln -s /zones/$MANTA/root/opt/smartdc/manta-deployment/networking /var/tmp/networking
cd /var/tmp/networking
./gen-coal.sh > configs/coal.json
./manta-net.sh ./configs/coal.json
cd -

# Now deploy...
zlogin $MANTA "bash -l -c \"/opt/smartdc/manta-deployment/bin/manta-init -e nobody@joyent.com -s coal -r coal -m fd2cc906-8938-11e3-beab-4359c665ac99\""
zlogin $MANTA "bash -l -c \"/opt/smartdc/manta-deployment/bin/manta-deploy-coal\""
sdc-ldap add -f /zones/$MANTA/root/opt/smartdc/manta-deployment/ufds/devs.ldif
