<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright 2016 Joyent, Inc.
-->

# VMware Fusion Image Templates

This directory contains template files used to create virtual machine images of
the Triton install and boot media suitable for use with VMware Fusion on Mac OS
X.  This configuration is commonly referred to as Cloud On A Laptop (COAL).

The `make_vmdk` script creates an appropriate VMDK wrapper file for the
USB disk image created during the build process.
