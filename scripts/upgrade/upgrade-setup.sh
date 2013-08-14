#!/usr/bin/bash
#
# upgrade-setup.sh: upgrades setup and configure scripts
# to current version, assumes a local zones/$ROLE/$FILE structure.

set -o errexit
set -o xtrace

ROLES="cnapi dapi vmapi workflow"

function copy_setup_files
{
    local SETUP=zones/$ROLE/setup
    local CONFIGURE=zones/$ROLE/configure
    local COMMON=setup.common

    cp $SETUP /usbkey/extra/$ROLE/setup
    cp $CONFIGURE /usbkey/extra/$ROLE/configure
    cp $COMMON /usbkey/extra/$ROLE/setup.common
}

for ROLE in $ROLES; do
    copy_setup_files
done
