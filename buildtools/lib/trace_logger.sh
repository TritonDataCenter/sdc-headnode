#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2015 Joyent, Inc.
#

#
# If TRACE is set in the environment, enable xtrace.  Additionally,
# assuming the current shell is bash version 4.1 or later, more advanced
# tracing output will be emitted and some additional features may be used:
#
#   TRACE_LOG   Send xtrace output to this file instead of stderr.
#   TRACE_FD    Send xtrace output to this fd instead of stderr.
#               The file descriptor must be open before the shell
#               script is started.
#
if [[ -n ${TRACE} ]]; then
    if [[ ${BASH_VERSINFO[0]} -ge 4 && ${BASH_VERSINFO[1]} -ge 1 ]]; then
        PS4=
        PS4="${PS4}"'[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: '
        PS4="${PS4}"'${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
        export PS4
        if [[ -n ${TRACE_LOG} ]]; then
            exec 4>>${TRACE_LOG}
            export BASH_XTRACEFD=4
        elif [[ -n ${TRACE_FD} ]]; then
            export BASH_XTRACEFD=${TRACE_FD}
        fi
    fi
    set -o xtrace
fi
