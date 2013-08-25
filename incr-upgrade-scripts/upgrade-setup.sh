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
    cp zones/$ROLE/setup /usbkey/extra/$ROLE/setup
    cp zones/$ROLE/configure /usbkey/extra/$ROLE/configure
    cp /usbkey/default/setup.common /usbkey/extra/$ROLE
    cp /usbkey/default/configure.common /usbkey/extra/$ROLE
    #TODO: should update /usbkey/extras/bashrc from /usbkey/rc/
}

cp default/* /usbkey/default
for ROLE in $ROLES; do
    copy_setup_files
done
