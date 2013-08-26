#!/usr/bin/bash
#
# upgrade-setup.sh: upgrades setup and configure scripts
# to current version, assumes a local zones/$ROLE/$FILE structure.

set -o errexit
set -o xtrace

# Note: must manually update this list for each upgrade. (TODO: have that
# come from a single upgrade-spec file that all scripts use.)
ROLES="dapi imgapi vmapi cloudapi cnapi workflow"

function copy_setup_files
{
    rm -f /usbkey/extra/$ROLE/setup
    cp zones/$ROLE/setup /usbkey/extra/$ROLE/setup
    rm -f /usbkey/extra/$ROLE/configure
    cp zones/$ROLE/configure /usbkey/extra/$ROLE/configure
    rm -f /usbkey/extra/$ROLE/setup.common
    cp /usbkey/default/setup.common /usbkey/extra/$ROLE/setup.common
    rm -f /usbkey/extra/$ROLE/configure.common
    cp /usbkey/default/configure.common /usbkey/extra/$ROLE/configure.common
    #TODO: should update /usbkey/extras/bashrc from /usbkey/rc/
}

cp default/* /usbkey/default
for ROLE in $ROLES; do
    copy_setup_files
done
