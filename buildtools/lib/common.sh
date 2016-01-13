#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2015 Joyent, Inc.
#

# This function wraps around tar, allowing us to handle platform specific
# weirdness.
ftar () {
    #
    # On Darwin (Mac OS X), trying to extract a tarball into a PCFS mountpoint
    # fails, as a result of tar trying create the `.` (dot) directory. This
    # appears to be a bug in how Mac implementes PCFS. Regardless, the
    # workaround to this is to include every directory and file with a name
    # that's longer than 2 characters. (`--exclude` doesn't seem to work on
    # Mac).
    #
    if [[ $(uname) = "Darwin" ]]; then
        tar --include="?*" $*
    elif [[ $(uname) = "SunOS" ]]; then
        # We must specify gtar, otherwise we will use the tar that ships
        # with illumos.
        gtar $*
    else
        tar $*
    fi
}
