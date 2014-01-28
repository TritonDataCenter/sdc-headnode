#!/usr/bin/bash
#
# Take this DC out of maintenance mode:
# - take cloudapi out of readonly mode
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- support routines

function fatal
{
    echo "$0: fatal error: $*" >&2
    exit 1
}


#---- mainline

[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

cloudapi_readonly_mode false

echo 'Done. DC is now *out of* maint mode.'
