<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2014, Joyent, Inc.
-->

# Template USB images

These images are used as templates to produce the sdc-headnode usbkey image.

## GRUB use & Licensing

The image templates contain a copy of the grub bootloader licensed under the GPLv2, a copy of which is available at `grub-LICENSE` or [online](http://www.gnu.org/licenses/gpl-2.0.html). The grub source code used is available at the [Ubuntu package archive](http://packages.ubuntu.com/lucid/grub)

## How to build a new image (Linux only)

IMPORTANT NOTES:

 - This assumes you're running Ubuntu 10.04 with enough disk space for the image + tarball
 - This assumes you've got grub 0.97 installed and not grub2
 - The output of the 'losetup' commands could change, if you get other /dev/loopX devices, replace as necessary
 - The output of the 'sfdisk -l -uS /dev/loopX' can change, update the geometry as needed in the grub input, and the start * sectorsize in losetup
 - You should only need to be typing stuff after the 'jill@headnode:~$' prompts

THE PROCESS:

jill@headnode:~$ sudo dd if=/dev/zero of=1gb.img bs=1000000 count=0 seek=1000
0+0 records in
0+0 records out
0 bytes (0 B) copied, 1.7285e-05 s, 0.0 kB/s
jill@headnode:~$ sudo losetup -vf 1gb.img
Loop device is /dev/loop0
jill@headnode:~$ printf ",,0x0c,-\n" | sudo sfdisk -H 255 -S 63 -D /dev/loop0
Checking that no-one is using this disk right now ...
BLKRRPART: Invalid argument
OK
Disk /dev/loop0: cannot get geometry

Disk /dev/loop0: 121 cylinders, 255 heads, 63 sectors/track

sfdisk: ERROR: sector 0 does not have an msdos signature
 /dev/loop0: unrecognized partition table type
Old situation:
No partitions found
New situation:
Units = cylinders of 8225280 bytes, blocks of 1024 bytes, counting from 0

   Device Boot Start     End   #cyls    #blocks   Id  System
/dev/loop0p1          0+    120     121-    971901    c  W95 FAT32 (LBA)
/dev/loop0p2          0       -       0          0    0  Empty
/dev/loop0p3          0       -       0          0    0  Empty
/dev/loop0p4          0       -       0          0    0  Empty
Warning: no primary partition is marked bootable (active)
This does not matter for LILO, but the DOS MBR will not boot this disk.
Successfully wrote the new partition table

Re-reading the partition table ...
BLKRRPART: Invalid argument

If you created or changed a DOS partition, /dev/foo7, say, then use dd(1)
to zero the first 512 bytes:  dd if=/dev/zero of=/dev/foo7 bs=512 count=1
(See fdisk(8).)
jill@headnode:~$ sudo sfdisk -l -uS /dev/loop0
Disk /dev/loop0: cannot get geometry

Disk /dev/loop0: 121 cylinders, 255 heads, 63 sectors/track
Units = sectors of 512 bytes, counting from 0

   Device Boot    Start       End   #sectors  Id  System
/dev/loop0p1            63   1943864    1943802   c  W95 FAT32 (LBA)
/dev/loop0p2             0         -          0   0  Empty
/dev/loop0p3             0         -          0   0  Empty
/dev/loop0p4             0         -          0   0  Empty
jill@headnode:~$ sudo losetup -fv -o $((63 * 512)) /dev/loop0
Loop device is /dev/loop1
jill@headnode:~$ sudo mkfs.vfat -F 32 -n "HEADNODE" /dev/loop1
mkfs.vfat 3.0.7 (24 Dec 2009)
Loop device does not match a floppy size, using default hd params
jill@headnode:~$ mkdir /tmp/mkimg
jill@headnode:~$ ln -s /dev/loop0 /tmp/mkimg/grubdev
jill@headnode:~$ ln -s /dev/loop1 /tmp/mkimg/grubdev1
jill@headnode:~$ sudo mount /tmp/mkimg/grubdev1 /mnt
jill@headnode:~$ sudo mkdir -p /mnt/boot/grub
jill@headnode:~$ sudo cp -a /usr/lib/grub/x86_64-pc/* /mnt/boot/grub/
jill@headnode:~$ printf "device (hd0) /tmp/mkimg/grubdev\ngeometry (hd0) 121 255 63\nroot (hd0,0)\nsetup (hd0)\n" | sudo grub --device-map=/dev/null

       [ Minimal BASH-like line editing is supported.   For
         the   first   word,  TAB  lists  possible  command
         completions.  Anywhere else TAB lists the possible
         completions of a device/filename. ]
grub> device (hd0) /tmp/mkimg/grubdev
grub> geometry (hd0) 121 255 63
drive 0x80: C/H/S = 121/255/63, The number of sectors = 1943865, /tmp/mkimg/grubdev
   Partition num: 0,  Filesystem type is fat, partition type 0xc
grub> root (hd0,0)
grub> setup (hd0)
 Checking if "/boot/grub/stage1" exists... yes
 Checking if "/boot/grub/stage2" exists... yes
 Checking if "/boot/grub/fat_stage1_5" exists... yes
 Running "embed /boot/grub/fat_stage1_5 (hd0)"...  16 sectors are embedded.
succeeded
 Running "install /boot/grub/stage1 (hd0) (hd0)1+16 p (hd0,0)/boot/grub/stage2 /boot/grub/menu.lst"... succeeded
    Done.
grub> jill@headnode:~$ sudo umount /mnt
jill@headnode:~$ sudo rm -rf /tmp/mkimg
jill@headnode:~$ sudo losetup -d /dev/loop1
jill@headnode:~$ sudo losetup -d /dev/loop0
jill@headnode:~$ GZIP=-9 tar -Szcf 1gb.img.tgz 1gb.img
jill@headnode:~$ ls -lh 1gb.img*
-rw-r--r-- 1 root root 954M 2011-01-03 16:38 1gb.img
-rw-r--r-- 1 jill jill 153K 2011-01-03 16:45 1gb.img.tgz
jill@headnode:~$

## Altering `.vmdk` files for a new image

The values that need to change in the vmdk file for the different images are:

RW 3906250 FLAT "<USB_IMAGE_FILE>" 0 (the second field here)

 - and -

ddb.geometry.cylinders = "3875"

to calculate the size (assuming your raw image is 2000000000 bytes):

    echo $((2000000000 / 512))

To calculate the cylinders:

    echo $((2000000000 / 512 / (16 * 63)))

And update these lines in a Xgb.coal.vmdk file.
