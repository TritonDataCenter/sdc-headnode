#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

PLATFORM=$(uname -s)

TAR="tar"
PCFSTAR="tar"

if [[ "$PLATFORM" == "SunOS" ]]; then
    SUCMD="pfexec"
    TAR="gtar"
    PCFSTAR="gtar"
elif [[ "$PLATFORM" == "Darwin" ]]; then
    SUCMD=""
    #
    # On Darwin (Mac OS X), trying to extract a tarball into a PCFS mountpoint
    # fails, as a result of tar trying create the `.` (dot) directory. This
    # appears to be a bug in how Mac implements PCFS.  Worse, the --include
    # work-around *only* works properly when one or fewer files are specified,
    # meaning we can't use the option generally.  --exclude doesn't work.
    #
    PCFSTAR="tar --include=?*"
elif [[ "$PLATFORM" == "Linux" ]]; then
    SUCMD="sudo"
fi

function fatal
{
    echo "$(basename $0): fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0
    fatal "error exit status $1 at line $2"
}

trap 'errexit $? $LINENO' EXIT

function rel2abs () {
    local abs_path end
    abs_path=$(unset CDPATH; cd `dirname $1` 2>/dev/null && pwd -P)
    [[ -z "$abs_path" ]] && return 1
    end=$(basename $1)
    echo "${abs_path%*/}/$end"
}

#
# The USB Image uses the GPT partitioning scheme and has the following slices:
#
# slice 1 - EFI System Partition (PCFS)
# slice 2 - Boot partition (no filesystem)
# slice 3 - Root partition (PCFS)
# slice 9 - reserved
#
# For our purposes, we want to mount slice 3, as that's where we'll be
# installing the platform image and other required software.
#
# Under SmartOS, we can't use labeled lofi or any other method to directly
# access the root filesystem, so we need to work from a temporary image.
#
function mount_root_image
{
    echo -n "==> Mounting new USB image... "
    if [[ "$PLATFORM" == "Darwin" ]]; then
        [ ! -d ${ROOT}/cache/tmp_volumes ] && mkdir -p ${ROOT}/cache/tmp_volumes
        hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage \
            $IMG_TMP_DIR/${OUTPUT_IMG} >/tmp/output.hdiattach.$$ 2>&1
        LOOPBACK=`grep "GUID_partition_scheme" /tmp/output.hdiattach.$$ \
            | awk '{ print $1 }'`
        MNT_DIR=$(mktemp -d ${ROOT}/cache/tmp_volumes/root.XXXX)
        mount -t msdos ${LOOPBACK}s3 $MNT_DIR
    elif [[ "$PLATFORM" == "Linux" ]]; then
        MNT_DIR="/tmp/sdc_image.$$"
        mkdir -p "$MNT_DIR"
        LOOPBACK=$IMG_TMP_DIR/${OUTPUT_IMG}
        OFFSET=$(parted -s -m "${LOOPBACK}" unit B print | grep fat32:root \
            | cut -f2 -d: | sed 's/.$//')
        ${SUCMD} mount -o "loop,offset=${OFFSET},uid=${EUID},gid=${GROUPS[0]}" \
            "${LOOPBACK}" "${MNT_DIR}"
    else
        mkdir -p ${MNT_DIR}
        ROOTOFF=$(nawk '$1 == "root" { print $3 }' <$IMG_TMP_DIR/$PARTMAP)
        ROOTSIZE=$(nawk '$1 == "root" { print $4 }' <$IMG_TMP_DIR/$PARTMAP)
        /usr/bin/dd bs=1048576 conv=notrunc \
            iseek=$(( $ROOTOFF / 1048576 )) count=$(( $ROOTSIZE / 1048576 )) \
            if=$IMG_TMP_DIR/${OUTPUT_IMG} of=$IMG_TMP_DIR/rootfs.img
        ${SUCMD} mount -F pcfs -o foldcase ${IMG_TMP_DIR}/rootfs.img ${MNT_DIR}
    fi
    echo "rootfs mounted on ${MNT_DIR}"
}

function unmount_loopback
{
    if mount | grep $MNT_DIR >/dev/null; then
        ${SUCMD} umount $MNT_DIR
    fi

    if [[ -n "$LOOPBACK" && "$PLATFORM" == "Darwin" ]]; then
        hdiutil detach ${LOOPBACK} || /usr/bin/true
    fi

    sync; sync
    LOOPBACK=
}

#
# On SmartOS, we need to copy our root fs back over into the original image
# file.
#
function unmount_root_image
{
    unmount_loopback

    if [[ "$PLATFORM" = "SunOS" ]]; then
        ROOTOFF=$(nawk '$1 == "root" { print $3 }' <$IMG_TMP_DIR/$PARTMAP)
        ROOTSIZE=$(nawk '$1 == "root" { print $4 }' <$IMG_TMP_DIR/$PARTMAP)

        /usr/bin/dd bs=1048576 conv=notrunc \
            oseek=$(( $ROOTOFF / 1048576 )) count=$(( $ROOTSIZE / 1048576 )) \
            if=$IMG_TMP_DIR/rootfs.img of=$IMG_TMP_DIR/${OUTPUT_IMG}
    fi
}
