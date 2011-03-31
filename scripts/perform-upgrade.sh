#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#
# This script takes an upgrade .tgz file that contains an upgrade directory
# that itself contains an upgrade.sh script and runs the script in the upgrade
# directory.
#

ERRORLOG="/tmp/perform_upgrade.$$.log"
TEMPDIR="/var/tmp/upgrade.$$"

#
# This is a fancy way of saying, send:
#
#  - a copy of stdout
#  - a copy of stderr
#  - xtrace output
#
# to the log file.
#
rm -f ${ERRORLOG}
exec > >(tee -a ${ERRORLOG}) 2>&1
exec 4>>${ERRORLOG}
BASH_XTRACEFD=4
export PS4='+(${BASH_SOURCE}:${LINENO}): ${SECONDS} ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o errexit
set -o pipefail
set -o xtrace

# consume the first arg (remainder get passed through)
input=$1
shift
if [[ -z ${input} || ! -f ${input} ]]; then
    sleep 0.1 # since output is going through tee and might lag slightly
    echo "Usage: $0 <upgrade file> [options]"
    exit 1
fi

function cleanup
{
    echo "==> Cleaning up"
    cd /
    rm -rf ${TEMPDIR}
    echo "==> DONE!"
}

function on_error
{
    echo "--> FATAL: an error occurred, see ${ERRORLOG} for details."
    exit 1
}

# get ready to rock
mkdir -p ${TEMPDIR}
trap cleanup EXIT
trap on_error ERR
echo "==> Logfile is ${ERRORLOG}"

# unpack upgrade file to and go to the temp dir
echo "==> Unpacking ${input} to ${TEMPDIR}"
gzcat ${input} | (cd ${TEMPDIR} && tar -xf -)
cd ${TEMPDIR}

if [[ ! -d ${TEMPDIR}/upgrade ]]; then
    echo "--> FATAL: ${input} contains no 'upgrade' directory.  Aborting!"
    exit 1
fi

if [[ ! -f ${TEMPDIR}/upgrade/upgrade.sh ]]; then
    echo "--> FATAL: ${input} contains no 'upgrade.sh' script.  Aborting!"
    exit 1
fi

echo "==> Running Upgrade Script"
cd ${TEMPDIR}/upgrade
bash ${TEMPDIR}/upgrade/upgrade.sh $@
echo "==> Upgrade script exited with status $?"

# unset trap
trap - EXIT
cleanup

exit 0
