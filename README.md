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

  - **One time only**: install VMWare Fusion, run it at least once to all it to
    establish its initial config, quit it and run the "CoaL vmware setup" script
    from the sdc.git repo:

            git clone git@github.com:joyent/sdc.git
            cd sdc
            ./tools/coal-mac-vmware-setup

  - Optionally, to automate setup:
    - create a `build.spec.local` file with the following contents: `{"answer-file": "answers.json"}`
    - copy one of the answers.json templates: `cp answers.json.tmpl.external answers.json`

    - see the [Build Specification][buildspec] and
      [Automating Headnode Setup][autosetup] sections below for more information.

  - `make coal` - this requires an internet connection, and will download
    images of all services. This can take quite some time. If this fails,
    please see the 'Build Prerequisites' and/or 'Debugging' sections below.

  - open `coal-master-TIMESTAMP-gSHA.vmwarevm`, select 'Live 64-bit' at the
    grub menu, and work through the interactive installer referring to [this
    documentation](). **Important**: while many answers are arbitrary, the
    networking questions require specific values for local development.

  - when setup completes, you can access the headnode via ssh: `ssh
    root@10.99.99.7` using the root password specified during setup.


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

### Build Specification: `build.spec` and `build.spec.local`

Some aspects of the configuration of the build, including which build artifacts
will be included in the resultant SDC installation media, are specified
declaritively.  The JSON file `build.spec` contains the default specification
of all build configuration, and is versioned in the repository.

During development, or as part of release engineering, particular elements of
the build specification may be overridden in another file: `build.spec.local`.
By re-specifying a subset of build configuration in this file, the behaviour of
a particular build run may be altered.  A useful example of `build.spec.local`
for local development is:

```
{
    "answer-file": "answers.json",
    "build-tgz": "false",
    "coal-memsize": 8192,
    "vmware_version": 5,
    "default-boot-option": 1,
    "clean-cache": true
}
```

In the example above,

  - `"answer-file"` is used to specify a setup answers file for inclusion in
    resultant installation media
  - `"build-tgz"` is used to disable the creation of a compressed tarball with
    the build results; instead, the resultant build artifacts will be left in
    output directories.
  - `"coal-memsize"` is used to set the VMware guest memory size to 8192MB
    (recommended if you plan to install a [Manta][manta] test environment.)
  - `"vmware_version"` specifies the version of VMware Fusion to target
  - `"default-boot-option"` selects the default grub boot option; a value of
    `1` selects the second entry in the menu: regular headnode boot

#### Build Artifacts

Three classes of build artifact may be described in the build specification
file: images, zones and files.

##### Images

Images, defined in the `"images"` key of the build specification file, refer to
specific image dataset streams (and their associated manifests) as published in
an IMGAPI service.  These artifacts are generally base images on which the
incremental dataset streams for core SDC zone datasets (specified in `"zones"`)
are based.

For example, the `sdc-multiarch` image (version `13.3.1`) has UUID
`"b4bdc598-8939-11e3-bea4-8341f6861379"`.  Its inclusion in the build is
specified with the following in `build.spec`:

```
{
    ...
    "images": {
        "multiarch-13.3.1": {
            "imgapi": "https://updates.joyent.com",
            "name": "sdc-multiarch",
            "version": "13.3.1",
            "uuid": "b4bdc598-8939-11e3-bea4-8341f6861379"
        },
        ...
    },
    ...
}
```

The `"uuid"` is the primary key used to locate the image in the IMGAPI service,
at the URL `"imgapi"`.  The `"name"` and `"version"` keys are checked against
the metadata retrieved in the manifest for this image.

The key used to name the object describing the image, i.e. `"multiarch-13.3.1"`
above, is used to name the symbolic link in the `cache/` directory that
later build steps will use to find the downloaded file.  The image definition
above will result in the creation of two symlinks:

- `cache/image.multiarch-13.3.1.imgmanifest`
- `cache/image.multiarch-13.3.1.zfs.gz`

##### Zones

The SDC headnode installation media includes images of various core zones.
These zone images are generally built by [Mountain Gorilla (MG)][mg], and the
resultant build artifacts are uploaded to a directory structure in
[Manta][manta].  Zone images are nominated for inclusion in the build via
the `"zones"` key in `build.spec`.

The simplest possible example is a zone where the MG build artifact name is the
same as the shipping filename, and the latest image is to be downloaded from
Manta.  One such example is the `"adminui"` zone:

```
{
    ...
    "zones": {
        "adminui": {},
        ...
    },
    ...
}
```

Some zones are known to MG by one name, but shipped in the installation media
by another (shorter) name.  The MG name can be provided with the `"jobname"`
key on a per-zone basis.  For example, the `"manatee"` zone comes from the
`"sdc-manatee"` MG target:

```
{
    ...
    "zones": {
        "manatee": {
            "jobname": "sdc-manatee"
        },
        ...
    },
    ...
}
```

Though the default source of zone images is [Manta][manta], the source may be
overridden on a per-build basis with the `"source"` key.  Zone images may be
acquired from the IMGAPI service at _updates.joyent.com_ by providing an image
UUID, e.g.

```
{
    ...
    "zones": {
        "adminui": {
            "source": "imgapi",
            "uuid": "ef967904-fd86-11e4-9c90-2bbf99b9e6cf"
        },
        ...
    },
    ...
}
```

Images may also be obtained from a local directory using the `"bits-dir"`
source.  This is primarily used by MG when building headnode images under
automation, where MG assembles the build artifacts in a local directory
structure.  If `"bits-dir"` is used, either through `"source"` for a specific
zone or via the `"override-all-sources"` top-level key, the `BITS_DIR`
environment variable must contain the path of a MG-style bits directory.  See
the source and documentation for [Mountain Gorilla][mg] for more details.

All of the above definitions will cause the download phase of build to store a
local copy of the zone dataset stream and manifest in the `cache/` directory,
using the original filename of the image, e.g. for `manatee`:

- `sdc-manatee-zfs-release-20150514-20150514T135531Z-g58e19ad.imgmanifest`
- `sdc-manatee-zfs-release-20150514-20150514T135531Z-g58e19ad.zfs.gz`

Note that the filename includes the MG job name and branch.  A symbolic link
will also be created to the downloaded file using the short name we specified,
i.e.

- `zone.manatee.imgmanifest`
- `zone.manatee.zfs.gz`

This symlink is used by subsequent build phases to locate the downloaded build
artifact.

##### Files

In addition to zone images and the base images on which they depend, the build
also includes various individual files.  These files are generally also the
output of [Mountain Gorilla (MG)][mg] build targets and are obtained either
from Manta (by default) or an MG-style `BITS_DIR`.

Files are specified in the `"files"` key of `build.spec`.  For example, the
SDC Agents are bundled together in a shell archive (shar) installer.  This
installer is produced as part of the `agentsshar` MG target.  The shar itself
is specified for inclusion with this entry:

```
{
    ...
    "files": {
        "agents": {
            "jobname": "agentsshar",
            "file": { "base": "agents", "ext": "sh" }
        },
        ...
    },
    ...
}
```

Note that the MG jobname is provided via `"jobname"` because it is different
from the short name of the file `"agents"`.  The download phase of the build
will download file into the `cache/` directory with its original file name,
e.g.:

- `agents-release-20150514-20150514T144745Z-gd067c0e.sh`

As with zones and images, a symbolic link will also be created for use during
subsequent phases of the build:

- `file.agents.sh`

By default, the `"manta-base-path"` top-level key is used to specify the
base directory where the downloader will look for build artifacts in Manta.
The default value for this key, as shipped in this repository, is
`"/Joyent_Dev/public/builds"`.  If you wish to include an artifact that
comes from a different Manta directory tree, you may specify the name of
an alternative top-level `build.spec` key on a per-file basis.

For example, Joyent ships firmware files for specific server hardware that is
not available under an opensource license.  As a result, these files are only
included in the commercially supported builds of SDC to Joyent customers.
The firmware artifact is stored in a different (Joyent-private) area of Manta,
and configured thus:

```
{
    ...
    "joyent-manta-base-path": "/Joyent_Dev/stor/builds",
    ...
    "files": {
        "firmware-tools": {
            "alt_manta_base": "joyent-manta-base-path",
            "file": { "base": "firmware-tools", "ext": "tgz" }
        },
        ...
    },
    ...
}
```

The `"alt_manta_base"` key specifies that the download phase of the build
should look in the path specified in `"joyent-manta-base-path"` for this
artifact, rather than the default key of `"manta-base-path"`.

#### Alternative Branch Selection

By default, the build artifacts sourced for inclusion in the headnode
installation media are from the _master_ branch of their respective source
repository.  [Mountain Gorilla][mg] includes the branch in names of
the build artifact directories and files.

The default branch may be overridden by specifying the `"bits-branch"` key.
The build branch for an individual zone or file may be overriden by specifying
`"branch"` in the artifact definition.  For example, to obtain artifacts from
the `release-20150514` branch for everything except the platform (and platform
boot tarball), the following could be used in `build.spec.local`:

```
{
    "bits-branch": "release-20150514",
    "files": {
        "platform": { "branch": "master" },
        "platboot": { "branch": "master" }
    }
}
```

#### Feature Definition

The build specification allows for the build process to be different based on a
set of named features.  These features can be enabled or disabled by default,
and may optionally be triggered by setting a nominated environment variable
when the build is run.

For example, the build supports the use of either a release build or a DEBUG
build of the operating system platform image.  This feature is defined, under
the top-level `"features"` key in `build.spec`, as follows:

```
{
    ...
    "features": {
        "debug-platform": {
            "enabled": false,
            "env": "DEBUG_BUILD"
        },
        ...
    },
    ...
}
```

The feature is named `"debug-platform"`, and may be enabled via the
`DEBUG_BUILD` environment variable.  It may also be overridden in
`build.spec.local` by specifying just the `"enabled"` property.  For example, in `build.spec.local`:

```
{
    "features": {
        "debug-platform": { "enabled": true }
    }
}
```

Features are generally used to enable the conditional inclusion of particular
sets of build artifacts, depending on the type of build.

#### Conditional Artifact Inclusion

Through the definition and activation of [Features](#feature-definition) via
the `"features"` key in the build specification, particular subsets of build
artifacts may be included or excluded.

For example, the `"debug-platform"` feature is used to determine whether the
release or DEBUG build of the operating system platform image is included in
the build.  Only one of these two platform images should be downloaded and
included in the build.

```
{
    ...
    "files": {
        "platform": {
            "if_not_feature": "debug-platform",
            "file": { "base": "platform", "ext": "tgz" }
        },
        "platform-debug": {
            "if_feature": "debug-platform",
            "file": { "base": "platform-debug", "ext": "tgz" }
        },
        ...
    },
    ...
}
```

The `"if_not_feature"` directive causes the `"platform"` build artifact to be
downloaded if, and only if, the `"debug-platform"` feature is disabled for this
build.  Conversely, the `"if_feature"` directive causes the `"platform-debug"`
artifact to become active when a DEBUG build is requested.  In this way, a
selection between two different build artifacts may be made based on features.
Feature activation is subsequently queried during later phases of the build
through the use of the `--feature` (`-f`) flag to `bin/buildspec`.

### Automating Headnode Setup: `answers.json`

The setup answers file (`answers.json`) provides information required for
headnode setup that would otherwise need to be entered by the user into the
interactive installer.  Particularly for local development work, it can be
convenient to specify these in advance.  The `answers.json.tmpl` and
`answers.json.tmpl.external` files provide usable examples for local
developement; the former configures only the admin network on setup, the latter
configures an external network as well.

The inclusion of a setup answers file in the resultant installation media is
controlled by the `"answer-file"` key in the build specification.

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

<!-- References -->

[mg]: https://github.com/joyent/mountain-gorilla
[manta]: https://github.com/joyent/manta
[buildspec]: #build-specification-buildspec-and-buildspeclocal
[autosetup]: #automating-headnode-setup-answersjson
