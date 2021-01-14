#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright 2021 Joyent, Inc.
#
# This script is run by sdc-usbkey update to update the copy of loader in the
# EFI System Partition if needed.
#

#
# We don't rely on the PI's usb-key.sh, as it may be too old.
# (even with an off-zpool boot `sdcadm platform` might have pushed an older PI
# on to the head node)

set -e

readonly loader_path="/boot/loader64.efi"
dryrun="no"
verbose="no"
update_esp="no"

function usage()
{
	echo "$0 [-nv] contentsdir mountpoint" >&2
	exit 2
}

#
# Identify the version of this USB key (if it is indeed a USB key).
#
# We do this by sniffing fixed offset within the MBR. If we have a (legacy)
# grub MBR, then we can look at offset 0x3e for COMPAT_VERSION_MAJOR and
# COMPAT_VERSION_MINOR (and we'll presume 3.2 as a minimum).
#
# If we're talking about a loader-based key, we'll peek at 0xfa AKA
# STAGE1_MBR_VERSION for format_image's IMAGE_MAJOR, which we expect to be 2.
#
# Unfortunately there's no standard way to find a version for other MBRs such as
# grub2's. In these cases we'll end up with a potentially random version here,
# so this key should not be trusted as ours until mounted and the path
# .joyusbkey is found.
#
function usb_key_version()
{
	local readonly devpath=$1
	local readonly mbr_sig_offset=0x1fe
	local readonly mbr_grub_offset=0x3e
	local readonly mbr_stage1_offset=0xfa
	local readonly mbr_grub_version=0203
	local readonly mbr_sig=aa55

	sig=$(echo $(/usr/bin/od -t x2 \
	    -j $mbr_sig_offset -A n -N 2 $devpath) )

	if [[ "$sig" != $mbr_sig ]]; then
		echo "unknown"
		return
	fi

	grub_val=$(echo $(/usr/bin/od -t x2 \
	    -j $mbr_grub_offset -A n -N 2 $devpath) )
	loader_major=$(echo $(/usr/bin/od -t x1 \
	    -j $mbr_stage1_offset -A n -N 1 $devpath) )

	if [[ "$grub_val" = $mbr_grub_version ]]; then
		echo "1"
		return
	fi

	echo $(( 0x$loader_major ))
}

#
# Mount the usbkey at the standard mount location (or whatever is specified).
#
function mount_usb_key()
{
	local mnt=$1

	if [[ -z "$mnt" ]]; then
		mnt=/mnt/$(svcprop -p "joyentfs/usb_mountpoint" \
		    "svc:/system/filesystem/smartdc:default")
	fi

	if [[ -f "$mnt/.joyliveusb" ]]; then
		echo $mnt
		return 0
	fi

	if ! mkdir -p $mnt; then
		echo "failed to mkdir $mnt" >&2
		return 1
	fi

	readonly alldisks=$(/usr/bin/disklist -a)

	for disk in $alldisks; do
		version=$(usb_key_version "/dev/dsk/${disk}p0")

		case $version in
		1) devpath="/dev/dsk/${disk}p1" ;;
		2) devpath="/dev/dsk/${disk}s2" ;;
		*) continue ;;
		esac

		fstyp="$(/usr/sbin/fstyp $devpath 2>/dev/null)"

		if [[ "$fstyp" != "pcfs" ]]; then
			continue
		fi

		/usr/sbin/mount -F pcfs -o foldcase,noatime $devpath $mnt \
		    2>/dev/null

		if [[ $? -ne 0 ]]; then
			continue
		fi

		if [[ -f $mnt/.joyliveusb ]]; then
			echo $mnt
			return 0
		fi

		if ! /usr/sbin/umount $mnt; then
			echo "Failed to unmount $mnt" >&2
			return 1
		fi
	done

	echo "Couldn't find USB key" >&2
	return 1
}

#
# Mount the EFI system partition, if there is one.  Note that since we need to
# peek at .joyliveusb to be sure, the only way to find a USB key is to mount its
# root first...
#
function mount_usb_key_esp()
{
	local readonly rootmnt=$(mount_usb_key)

	if [[ $? -ne 0 ]]; then
		return 1
	fi

	dev=$(mount | nawk "\$0~\"^$rootmnt\" { print \$3 ; }")
	dsk=${dev%[ps]?}

	mnt=/tmp/mnt.$$

	if ! mkdir -p $mnt; then
		echo "failed to mkdir $mnt" >&2
		return 1
	fi

	version=$(usb_key_version ${dsk}p0)

	#
	# If this key is still grub, then we don't have an ESP, but we shouldn't
	# report an error.
	#
	if [[ "$version" = "1" ]]; then
		rmdir $mnt
		return 0
	fi

	/usr/sbin/mount -F pcfs -o foldcase,noatime ${dsk}s0 $mnt

	if [[ $? -ne 0 ]]; then
		rmdir $mnt
		return 1
	fi

	echo $mnt
	return 0
}

while getopts "nv" opt; do
	case $opt in
	n) dryrun="yes" ;;
	v) verbose="yes" ;;
	*) usage ;;
	esac
done

shift $((OPTIND-1))
contents=$1
shift
mountpoint=$1

[[ -n "$contents" ]] || usage
[[ -n "$mountpoint" ]] || usage

old_boot_ver=$(cat $mountpoint/etc/version/boot 2>&1 || true)

if [[ -z "$old_boot_ver" ]]; then
	exit 0
fi

if cmp $mountpoint/$loader_path $contents/$loader_path >/dev/null; then
	if [[ "$verbose" = "yes" ]]; then
		echo "$loader_path is unchanged; skipping ESP update"
	fi

	exit 0
fi

if [[ "$verbose" = "yes" ]]; then
	echo "Updating loader ESP because $loader_path changed"
fi

if [[ "$dryrun" = "yes" ]]; then
	exit 0
fi

# If we booted from a ZFS pool, figure that out now.
bootpool=$(bootparams | awk -F= '/^triton_bootpool=/ {print $2}')
if [[ "$bootpool" != "" ]]; then
	# Boots off of a zpool.  Do it all inside here.
	bootfs=/"$bootpool"/boot

	# Reality checks.
	if [[ ! -d /"$bootfs" ||
		! -f /"$bootfs"/.joyusbkey ]]; then
		echo "The /$bootfs directory doesn't exist," \
			"or has other problems" >&2
		exit 1
	fi

	# Update bootfs loader bits
	files=" \
		etc/version/boot \
		boot/pmbr \
		boot/gptzfsboot \
		boot/loader64.efi
		"
	for a in "$files"; do
		cp -f "$contents"/"$a" /"$bootfs"/"$a"
		if [[ $? != 0 ]];
			echo "Error copying $a from $contents to $bootfs" >&2
			exit 1
		fi
	done

	# Then update the pool using piadm(1M)
	piadm bootable -r $bootpool
	exit $?
fi

esp=$(mount_usb_key_esp)
ret=$?

if [[ $ret -ne 0 ]]; then
	exit $ret
fi

#
# An empty result means that key isn't loader-based, so there's no ESP to
# update...
#
if [[ -z "$esp" ]]; then
	if [[ "$verbose" = "yes" ]]; then
		echo "Key is legacy type; skipping ESP update"
	fi
	exit 0
fi

if ! cp -f $contents/$loader_path $esp/efi/boot/bootx64.efi; then
	echo "Failed to copy $contents/$loader_path to ESP" >&2
	umount $esp
	rmdir $esp
	exit 1
fi

if ! umount $esp; then
	echo "Failed to unmount $esp" >&2
	exit 1
fi

rmdir $esp
exit 0
