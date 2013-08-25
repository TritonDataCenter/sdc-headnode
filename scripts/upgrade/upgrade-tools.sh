#!/usr/bin/bash
#
# Upgrade the tools from usb-headnode.git/tools/... to /opt/smartdc/bin
# This requires a local copy of that 'tools/...' dir.
#
# Limitation: for now we are ignore updates to tools-modules/... and
# tools-man/...
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


#---- support stuff

function fatal
{
    echo "$0: fatal error: $*"
    exit 1
}


#---- mainline

[[ ! -d "./tools" ]] && fatal "there is no longer 'tools' dir!"

for tool in $(ls -1 ./tools); do
    new=./tools/$tool
    old=/opt/smartdc/bin/$tool
    if [[ -n "$(diff $old $new || true)" ]]; then
        echo ""
        echo "# upgrade tool '$old'"
        diff -u $old $new || true
        cp -rH $new $old
    fi
done
