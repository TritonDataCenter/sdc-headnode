# SDC Upgrade Scripts

These scripts will be used for the JPC upgrades on June 5th.  There's a fair bit
of work to do to make them sufficiently general.

To run an upgrade:

    cd /usbkey/scripts/upgrade
    ./download-all.sh
    ./upgrade-sapi.sh <datacenter name>
    ./upgrade-all.sh

## Addendum June 12

Used to upgrade us-beta-4 to latest.

Used (with various images commented out) to upgrade CNAPI in production to fix critical memory leak.
