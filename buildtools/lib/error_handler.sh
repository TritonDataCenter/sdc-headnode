#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2015 Joyent, Inc.
#

function stack_trace
{
    set +o xtrace

    (( cnt = ${#FUNCNAME[@]} ))
    (( i = 0 ))
    while (( i < cnt )); do
        printf '  [%3d] %s\n' "${i}" "${FUNCNAME[i]}"
        if (( i > 0 )); then
            line="${BASH_LINENO[$((i - 1))]}"
        else
            line="${LINENO}"
        fi
        printf '        (file "%s" line %d)\n' "${BASH_SOURCE[i]}" "${line}"
        (( i++ ))
    done
}

function fatal
{
    # Disable error traps from here on:
    set +o xtrace
    set +o errexit
    set +o errtrace
    trap '' ERR

    echo "$(basename $0): fatal error: $*" >&2
    stack_trace
    exit 1
}

function trap_err
{
    st=$?
    fatal "exit status ${st} at line ${BASH_LINENO[0]}"
}

#
# We set errexit (a.k.a. "set -e") to force an exit on error conditions, but
# there are many important error conditions that this does not capture --
# first among them failures within a pipeline (only the exit status of the
# final stage is propagated).  To exit on these failures, we also set
# "pipefail" (a very useful option introduced to bash as of version 3 that
# propagates any non-zero exit values in a pipeline).
#
set -o errexit
set -o pipefail

shopt -s extglob

#
# Install our error handling trap, so that we can have stack traces on
# failures.  We set "errtrace" so that the ERR trap handler is inherited
# by each function call.
#
trap trap_err ERR
set -o errtrace
