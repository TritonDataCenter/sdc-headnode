<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2014, Joyent, Inc.
-->

# sdc-headnode

This repository is part of the Joyent SmartDataCenter project (SDC).  For
contribution guidelines, issues, and general documentation, visit the main
[SDC](http://github.com/joyent/sdc) project page.

This is the repository for building headnode images for SDC, and the intial
setup and configuration of the headnode itself.

## Quickstart (on OS X)

To create a VM for local development work – commonly called 'coal' (Cloud On A Laptop) – follow these steps:

  - **One time only**: install VMWare Fusion, run it at least once to all it to establish its initial config, quit it and run `coal/coal-vmware-setup`.

  - Optionally, to automate setup:
    - create a `build.spec.local` file with the following contents: `{"answers-file": "answers.json"}`
    - copy one of the answers.json templates: `cp answers.json.tmpl.external answers.json`
    - see the 'Optional Coniguration & Automated Setup' section below for more information.

  - `make coal` - this requires an internet connection, and will download images of all services. This can take quite some time. If this fails, please see the 'Build Prerequisites' and/or 'Debugging' sections below.

  - open `coal-master-TIMESTAMP-gSHA.vmwarevm`, select 'Live 64-bit' at the grub menu, and work through the interactive installer referring to [this documentation](). **Important**: while many answers are arbitrary, the networking questions require specific values for local development.

  - when setup completes, you can access the headnode via ssh: `ssh root@10.99.99.7` using the root password specified during setup.

## Less-quick start

There are three main build products from this repo:

  - `make usb` - outputs a usb image tarball
  - `make coal` - outputs a coal image for use with VMWare
  - `make incr-upgrade` - outputs a tarball with scripts and tools for incremental upgrades of services on existing headnodes.

### Build prerequisites

On OS X:

  - A recent version of node (>= 0.10.26, preferably latest).
  - The [json](http://trentm.com/json/) CLI tool.
  - the [XCode Command Line Tools](https://developer.apple.com/downloads/index.action) [Apple sign-in required]. Alternately, any setup of the GNU toolchain sufficient to build a moderately-complex project should also work.

On SmartOS:

First you must create a suitable build zone:
  - vmapi or GZ vmadm access to set filesystem permissions on the build zone
  - provision a zone, params XXX

Then to set up the zone:
  - A recent version of node (>= 0.10.26, preferably latest).
  - The [json](http://trentm.com/json/) CLI tool.

### Optional configuration & automated setup

The default build should produce a usable result, but there are a number of parameters you can configure for specific behaviour or performance reasons. The two main files involved are:

  - `build.spec.local` which controls aspects of the build
  - `answers.json` which can automate the setup of the headnode

Both files are JSON.

#### `build.spec` and `build.spec.local`

Keys in `build.spec` can be overridden in `build.spec.local` to customize the behaviour of the build. A useful example for local developement is:

```
{
    "answer-file": "answers.json",
    "build-tgz": "false",
    "coal-memsize": 8192,
    "vmware_version": 5,
    "keep-bits": 1,
    "default-boot-option": 1
}
```
Respectively, this file:

  - specifies where to find the setup answers file
  - does not tar/gzip the results of the build
  - sets the vmware memory size to 8192MB (recommended if you plan to install a [Manta](https://github.com/joyent/manta) test environment.)
  - specifies the vmware version to target
  - keeps only the most-recently downloaded images (to save space)
  - configures grub to boot as a headnode by default

Some other useful settings are:

```
    "moray-image": "moray/moray-zfs-.*manifest",
    "napi-image": "napi/napi-zfs-.*manifest",
    "papi-image": "papi/papi-zfs-.*manifest",
```
And similarly for all the images used on the headnode. The images used in the build default to the latest available builds of those services, but can be overridden to use branch builds, or images on the local filesystem:
```
   "moray-image": "moray/BRANCH-NAME/moray-zfs-.*manifest",
   "napi-image": "/Users/mbs/headnode-cache/moray-zfs-master-20130401T104924Z-g1695958.zfs.dsmanifest"
```

#### `answers.json`

`answers.json` provides information required for headnode setup that is otherwise gathered by the interactive installer. Particularly for local development work, it can be convenient to specify these in advance. The `answers.json.tmpl` and `answers.json.tmpl.external` files provide usable examples for local developement; the former configures only the admin network on setup, the latter configures an external network as well.

### Debugging build failures

Build logs are located in `sdc-headnode/log/build.log.TIMESTAMP`, and the logs of the latest *successful* build are symlinked at `sdc-headnode/log/latest`.

Setting `TRACE=true` in the environment will produce verbose output from bash.

### Debugging setup failures

Headnode setup is run by the `/system/smartdc/init` SMF service, and its logs can be accessed at:
```
[root@headnode (coal) ~]# svcs -L init
/var/svc/log/system-smartdc-init:default.log
```

The failure may have occurred in one of the zones being installed, rather than in the setup process itself. In that case, the relevant logs are often inside the zone (accessible via first `zlogin $UUID`):
  - `svcs -L mdata:fetch` -- fetches the user-script
  - `svcs -L mdata:execute` -- executes the user-script
  - `/var/svc/setup.log` -- the output from the setup script
  - `/var/svc/setup_complete` -- if this file exists (should be empty) setup thinks it succeeded

## Developing for the headnode

Development in this repo is typically to alter setup and bootstrap of the system. Setup scripts reside on a USB key typically mounted at `/mnt/usbkey`, and are copied onto the headnode at `/usbkey`.

To test changes to setup procedures without a complete rebuild, you can:
  - mount the usbkey (if required) using `/usbkey/scripts/mount-usb.sh`
  - copy your modifications over the existing scripts
  - run `sdc-factory-reset` to re-run the setup process
