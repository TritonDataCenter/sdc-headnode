#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2019, Joyent, Inc.
#

set -o errexit
set -o pipefail
# BASHSTYLED
#export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -o xtrace

function fatal()
{
        printf "%s\n" "$1" 1>&2
        exit 1
}

function usage()
{
    print -u2 "Usage: $0 <platform buildstamp>"
    print -u2 "(eg. '$0 20110318T170209Z')"
    exit 1
}

if [[ "$1" = "-n" ]]; then
    dryrun=true
    shift
fi

function onexit
{
    if [[ ${mounted} == "true" ]]; then
        echo "==> Unmounting USB Key"
        /opt/smartdc/bin/sdc-usbkey unmount ||
            echo "failed to unmount USB key" >&2
    fi

    echo "==> Done!"
}

# replace a loader conf value
function edit_param
{
    local readonly file="$1"
    local readonly key="$2"
    local readonly value="$3"
    if ! /usr/bin/grep "^\s*$key\s*=\s*" $file >/dev/null; then
        echo "$key=\"$value\"" >>$file
        return
    fi

    /usr/bin/sed -i '' "s+^\s*$key\s*=.*+$key=\"$value\"+" $file
}

function config_loader
{
    local readonly kernel="i86pc/kernel/amd64/unix"
    local readonly archive="i86pc/amd64/boot_archive"
    local readonly tmpconf=$(mktemp /tmp/loader.conf.XXXX)

    echo "==> Updating Loader configuration"

    cp ${usbmnt}/boot/loader.conf $tmpconf

    edit_param $tmpconf bootfile "/os/$version/platform/$kernel"
    edit_param $tmpconf boot_archive_name "/os/$version/platform/$archive"
    edit_param $tmpconf boot_archive.hash_name \
        "/os/$version/platform/${archive}.hash"
    edit_param $tmpconf platform-version "$version"

    #
    # Check whether the currently running (soon-to-be previous) version
    # exists on the USB key.  This should always be the case on production
    # bits as we set the rollback target to the currently running platform and
    # sdcadm will prevent the user from removing the currently running platform
    # (though it can be overridden with the --force option).  The more likely
    # place we'd see this is with developer platform images where there can
    # be skew between the platform buildstamp and the version stamp that gets
    # encoded into unix.  When that happens, the buildstamp of the currently
    # running platform may not match the output of "uname -v".  So this code
    # attempts to handle these (admittedly rare) corner cases to ensure that:
    #
    # 1) The boot entry for the rollback target always points to a valid path
    #    on the USB key
    # 2) Or if we've found ourselves in a situation where there is only one
    #    platform on the USB key, then we don't create a rollback boot entry
    #    at all.
    #
    # XXX - the more likely place this could occur is after a
    # "sdcadm platform remove" - for example, consider the case where a CN
    # has a USB key with two platform images (A and B)
    #
    # CN is currently running image A.
    # CN is then assigned image B.
    # Image A gets set as the rollback target in the boot loder config
    # CN reboots and is now running image B.
    #
    # At his point there is nothing to prevent the admin from removing image A.
    # which would invalidate the rollback boot menu entry.  So we have some
    # more work to do in sdcadm to fully handle these cases.
    #
    local rollback_vers=$current_version
    if [[ ! -d $usbmnt/os/$rollback_vers ]]; then
        rollback_vers=$(ls -1 $usbmnt/os | tr "[:lower:]" "[:upper:]" | \
            grep -v $version | sort | tail -1)
    fi

    if [[ -n $rollback_vers ]]; then
        edit_param $tmpconf prev-platform "/os/$rollback_vers/platform/$kernel"
        edit_param $tmpconf prev-archive "/os/$rollback_vers/platform/$archive"
        edit_param $tmpconf prev-hash \
            "/os/$rollback_vers/platform/${archive}.hash"
        edit_param $tmpconf prev-version "$rollback_vers"
    fi

    #
    # If it's a dryrun, just print the new Loader configuration.  Otherwise,
    # copy the new configuration into place.
    #
    if [[ -n "${dryrun}" ]]; then
        cat $tmpconf
    else
        cp -f $tmpconf ${usbmnt}/boot/loader.conf
    fi

    rm -f $tmpconf
}

function config_grub
{
    echo "==> Creating new GRUB configuration"
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
}

version=$1
[[ -z ${version} ]] && usage

# -U is a private option to bypass cnapi update during upgrade.
UPGRADE=0
while getopts "U" opt
do
    case "$opt" in
        U) UPGRADE=1 ;;
        *)
            print -u2 "invalid option"
            usage
            ;;
    esac
done
shift $(($OPTIND - 1))

current_version=$(uname -v | cut -d '_' -f 2)

# BEGIN BASHSTYLED
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"
# END BASHSTYLED
mounted="false"
hashfile="/platform/i86pc/amd64/boot_archive.hash"
menulst="${usbmnt}/boot/grub/menu.lst"
loader_conf="${usbmnt}/boot/loader.conf"

mnt_status=$(/opt/smartdc/bin/sdc-usbkey status)
[ $? != 0 ] && fatal "failed to get USB key status"
if [[ $mnt_status = "unmounted" ]]; then
    echo "==> Mounting USB key"
    /opt/smartdc/bin/sdc-usbkey mount
    [ $? != 0 ] && fatal "failed to mount USB key"
    mounted="true"
fi

trap onexit EXIT

[[ ! -d ${usbmnt}/os/${version} ]] && \
    fatal "==> FATAL ${usbmnt}/os/${version} does not exist."


readonly usb_version=$(/opt/smartdc/bin/sdc-usbkey status -j | json version)

case "$usb_version" in
    1) config_grub ;;
    2) config_loader ;;
    *) echo "unknown USB key version $usb_version" >&2
       /opt/smartdc/bin/sdc-usbkey unmount
       exit 1 ;;
esac

# If upgrading, skip cnapi update, we're done now.
[ $UPGRADE -eq 1 ] && exit 0

echo "==> Updating cnapi"
. /lib/sdc/config.sh
load_sdc_config

uuid=`curl -s http://${CONFIG_cnapi_admin_ips}/servers | \
    json -a headnode uuid | nawk '{if ($1 == "true") print $2}' 2>/dev/null`

[[ -z "${uuid}" ]] && \
    fatal "==> FATAL unable to determine headnode UUID from cnapi."

if [[ -n "${dryrun}" ]]; then
    doit="echo"
fi

${doit} curl -s http://${CONFIG_cnapi_admin_ips}/servers/${uuid} \
    -X POST -d boot_platform=${version} >/dev/null 2>&1

exit 0
