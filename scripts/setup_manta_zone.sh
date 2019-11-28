#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

#
# setup_manta_zone.sh: bootstrap a manta deployment zone
#
# This script has been replaced by "sdcadm post-setup manta --mantav1".
#

echo '* * *
error: setup_manta_zone.sh has been replaced
Use the following to create a manta deployment zone:

    sdcadm post-setup common-external-nics  # enable downloading service images
    sdcadm post-setup manta --mantav1
* * *'

exit 1
