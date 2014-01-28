#!/usr/bin/bash
#
# Upgrade the tools from usb-headnode.git/tools/... to /opt/smartdc/bin
# This requires a local copy of that 'tools/...' dir.
#
# Limitation: for now we are ignoring updates to tools-modules/... and
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

[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"
[[ ! -d "./tools" ]] && fatal "there is no './tools' dir from which to upgrade!"

# Guard on having an 'sdc' zone. If the HN doesn't have one, then the new
# tools will all be broken.
$(vmadm lookup -1 state=running tags.smartdc_role=sdc >/dev/null 2>&1) \
    || fatal "this SDC headnode does not have an 'sdc' zone, cannot upgrade to the latest tools"

for tool in $(ls -1 ./tools); do
    new=./tools/$tool
    old=/opt/smartdc/bin/$tool
    if [[ ! -f $old || -n "$(diff $old $new || true)" ]]; then
        echo ""
        echo "# upgrade tool '$old'"
        [[ -f $old ]] && diff -u $old $new || true
        if [[ "$tool" == "sdc-imgadm" ]]; then
            # In older SDC7, sdc-imgadm was a symlink. Remove the target
            # to be sure we get the actual source file type.
            rm -f $old
        fi
        cp -rP $new $old
    fi
done

[[ ! -d "./scripts" ]] && fatal "there is no './scripts' dir from which to upgrade!"


echo 'Mount USB key and upgrade [/mnt]/usbkey/scripts.'

/usbkey/scripts/mount-usb.sh
if [[ ! -d "/mnt/usbkey/scripts" ]]; then
    echo "unable to mount /mnt/usbkey" >&2
    exit 1
fi

cp -Rp /usbkey/scripts pre-upgrade.scripts.$(date +%s)
rm -rf /mnt/usbkey/scripts /usbkey/scripts
cp -Rp scripts /mnt/usbkey/scripts
cp -Rp scripts /usbkey/scripts

umount /mnt/usbkey

