#!/bin/bash
#
# Copyright (c) 2013 Joyent Inc., All rights reserved.
#

set -o errexit
set -o pipefail
# BASHSTYLED
#export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -o xtrace

if [[ "$1" = "-n" ]]; then
    dryrun=true
    shift
fi

version="${1^^}"
if [[ -z "${version}" ]]; then
    echo "Usage: $0 <platform buildstamp>"
    echo "(eg. '$0 20110318T170209Z')"
    exit 1
fi

current_version=$(uname -v | cut -d '_' -f 2)

# BEGIN BASHSTYLED
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
# END BASHSTYLED
mounted="false"
hashfile="/platform/i86pc/amd64/boot_archive.hash"
menulst="${usbmnt}/boot/grub/menu.lst"

function onexit
{
    if [[ ${mounted} == "true" ]]; then
        echo "==> Unmounting USB Key"
        umount /mnt/usbkey
    fi

    echo "==> Done!"
}

# -U is a private option to bypass cnapi update during upgrade.
UPGRADE=0
while getopts "U" opt
do
    case "$opt" in
        U) UPGRADE=1;;
        *) echo "invalid option"
           exit 1
           ;;
    esac
done
shift $(($OPTIND - 1))

version=$1
if [[ -z ${version} ]]; then
    echo "Usage: $0 <platform buildstamp>"
    echo "(eg. '$0 20110318T170209Z')"
    exit 1
fi

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

trap onexit EXIT

if [[ ! -d ${usbmnt}/os/${version} ]]; then
    echo "==> FATAL ${usbmnt}/os/${version} does not exist."
    exit 1
fi

echo "==> Creating new menu.lst"
if [[ -z "${dryrun}" ]]; then
    rm -f ${usbmnt}/boot/grub/menu.lst
    tomenulst=">> ${menulst}"
fi
while read input; do
    set -- $input
    if [[ "$1" = "#PREV" ]]; then
        _thisversion="${current_version}"
    else
        _thisversion="${version}"
    fi
    output=$(echo "$input" | sed \
        -e "s|/PLATFORM/|/os/${version}/platform/|" \
        -e "s|/PREV_PLATFORM/|/os/${current_version}/platform/|" \
        -e "s|PREV_PLATFORM_VERSION|${current_version}|" \
        -e "s|^#PREV ||")
    set -- $output
    if [[ "$1" = "module" ]] && [[ "${2##*.}" = "hash" ]] && \
        [[ ! -f "${usbcpy}/os/${_thisversion}${hashfile}" ]]; then
        continue
    fi
    eval echo '${output}' "${tomenulst}"
done < "${menulst}.tmpl"

# If upgrading, skip cnapi update, we're done now.
[ $UPGRADE -eq 1 ] && exit 0

echo "==> Updating cnapi"
. /lib/sdc/config.sh
load_sdc_config

uuid=`curl -s http://${CONFIG_cnapi_admin_ips}/servers | \
    json -a headnode uuid | nawk '{if ($1 == "true") print $2}' 2>/dev/null`

if [[ -z "${uuid}" ]]; then
    echo "==> FATAL unable to determine headnode UUID from cnapi."
    exit 1
fi

if [[ -n "${dryrun}" ]]; then
	doit="echo"
fi

${doit} curl -s http://${CONFIG_cnapi_admin_ips}/servers/${uuid} \
    -X POST -d boot_platform=${version} >/dev/null 2>&1

exit 0
