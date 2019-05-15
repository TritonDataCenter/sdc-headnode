# sdc-headnode

This repository is part of the Joyent Triton project. See the [contribution
guidelines](https://github.com/joyent/triton/blob/master/CONTRIBUTING.md) --
*Triton does not use GitHub PRs* -- and general documentation at the main
[Triton project](https://github.com/joyent/triton) page.

This is the repository for building headnode images for Triton, and the initial
setup and configuration of the headnode itself.


## Quickstart (on OS X)

To create a VM for local development work – commonly called 'coal' (Cloud On A Laptop) – follow these steps:

  - **One time only**: install VMware Fusion, run it at least once to allow it
    to establish its initial config, quit it and run the "CoaL VMware setup"
    script from the triton.git repo:

            git clone git@github.com:joyent/triton.git
            cd triton
            ./tools/coal-mac-vmware-setup

  - Optionally, to automate setup:

    - `echo '{"answer-file": "answers.json.tmpl.external"}' >build.spec.local`

    - see the [Build Specification][buildspec] and
      [Automating Headnode Setup][autosetup] sections below for more information.

  - `make coal` - this requires an Internet connection, and will download
    images of all services. This can take quite some time. If this fails,
    please see the 'Build Prerequisites' and/or 'Debugging' sections below.

  - `open coal-master-TIMESTAMP-gSHA.vmwarevm`, let the boot time out, then work
    through the interactive installer if you didn't provide an answer file,
    referring to [this documentation][coal-setup.md]. **Important**: while many
    answers are arbitrary, the networking questions require specific values
    for local development.

  - note that the console defaults to `ttyb` a.k.a. `socket.serial1`. You can
    use something like [sercons][https://github.com/jclulow/vmware-sercons] to
    connect to this.

  - when setup completes, you can access the headnode via ssh: `ssh
    root@10.99.99.7` using the root password specified during setup.


## Less-quick start

There are three main build products from this repo:

  - `make usb` - outputs a USB image tarball
  - `make coal` - outputs a coal image for use with VMware

### Build prerequisites

On OS X:

  - A recent version of node (>= 0.10.26, preferably latest).
  - The [json](http://trentm.com/json/) CLI tool.
  - the [XCode Command Line Tools](https://developer.apple.com/downloads/index.action) [Apple sign-in required]. Alternately, any setup of the GNU toolchain sufficient to build a moderately-complex project should also work.

On Linux:
  - A recent version of node (>= 0.12, preferably latest).
  - The [json](http://trentm.com/json/) CLI tool.
  - The gcc/clang build toolchain (for building the native node modules)

On SmartOS:

First you must create a suitable build zone:
  - VMAPI or GZ vmadm access to set filesystem permissions on the build zone
  - provision a zone, params XXX

Then to set up the zone:
  - A recent version of node (>= 0.10.26, preferably latest).
  - The [json](http://trentm.com/json/) CLI tool.
  - The 'pigz' program available somewhere on $PATH

### Build Specification: `build.spec` and `build.spec.local`

Some aspects of the configuration of the build, including which build artefacts
will be included in the resultant Triton installation media, are specified
declaratively.  The JSON file `build.spec` contains the default specification
of all build configuration, and is versioned in the repository.

During development, or as part of release engineering, particular elements of
the build specification may be overridden in another file: `build.spec.local`.
By re-specifying a subset of build configuration in this file, the behaviour of
a particular build run may be altered.  For example:

```
{
    "answer-file": "answers.json.tmpl.external",
    "build-tgz": "false",
    "coal-memsize": 8192,
    "vmware_version": 7,
    "clean-cache": true,
    "ipxe": false,
    "console": "ttya"
}
```

In the example above,

  - `"answer-file"` is used to specify a setup answers file for inclusion in
    resultant installation media; `answers.json.tmpl.external` is suitable for
    a standard COAL setup
  - `"build-tgz"` is used to disable the creation of a compressed tarball with
    the build results; instead, the resultant build artefacts will be left in
    output directories. This can be very useful when rsync'ing a COAL build
  - `"coal-memsize"` is used to set the VMware guest memory size to 8192MB
    (recommended if you plan to install a [Manta][manta] test environment.)
  - `"vmware_version"` specifies the version of VMware Fusion to target.
    See <https://kb.vmware.com/s/article/1003746> for mapping of Virtual
    Hardware Version to VMware releases. Note that `vmware_version=7`,
    corresponding to hardware version 11, is required for Bhyve VMs to work.
  - COAL defaults to USB boot; `"ipxe"` modifies this default
  - COAL defaults to serial console, using `ttyb`. Use `text` for VGA console

#### Build Artefacts

Two classes of build artefact may be described in the build specification
file: zones and files.

##### Zones

The Triton headnode installation media includes images of various core zones.
These zone images are are uploaded to a directory structure in [Manta][manta].
Zone images are nominated for inclusion in the build via the `"zones"` key
in `build.spec`.

The simplest possible example is a zone where the MG build artefact name is the
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
            "uuid": "ef967904-fd86-11e4-9c90-2bbf99b9e6cf",
            "channel": "experimental"   // optional IMGAPI channel
        },
        ...
    },
    ...
}
```

Images may also be obtained from a local directory using the `"bits-dir"`
source.  The directory layout mirrors that of the Manta hierarchy used by
other Manta/Triton components, and eng.git's `"bits-upload.sh"` script.
If `"bits-dir"` is used, either through `"source"` for a specific
zone or via the `"override-all-sources"` top-level key, the `SOURCE_BITS_DIR`
environment variable must contain the path of a MG-style bits directory.  See
the source and documentation for [Mountain Gorilla][mg] for more details.

The above definitions will cause the download phase of the build to
store a local copy of the zone dataset stream and manifest in the `cache/`
directory, using the original filename of the image, e.g. for `manatee`:

- `sdc-manatee-zfs-release-20150514-20150514T135531Z-g58e19ad.imgmanifest`
- `sdc-manatee-zfs-release-20150514-20150514T135531Z-g58e19ad.zfs.gz`

Note that the filename includes the MG job name and branch. A symbolic link
will also be created to the downloaded files using the short name we specified,
i.e.

- `zone.manatee.imgmanifest`
- `zone.manatee.imgfile`


In addition, any origin images of the zone image will also be downloaded and
placed in the `cache/` directory, e.g.:

- 04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f.imgmanifest
- 04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f.imgfile

Likewise, a symbolic link will be created to the download origin image files:

- image.04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f.imgmanifest
- image.04a48d7d-6bb5-4e83-8c3b-e60a99e0f48f.imgfile

These symlinks are used by subsequent build phases to locate the downloaded
build artefact.


##### Files

In addition to zone images and the base images on which they depend, the build
also includes various individual files.  These files are generally also the
output of [Mountain Gorilla (MG)][mg] build targets and are obtained either
from Manta (by default) or a directory pointed to by `SOURCE_BITS_DIR`.

Files are specified in the `"files"` key of `build.spec`.  For example, the
Triton Agents are bundled together in a shell archive (shar) installer.  This
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
base directory where the downloader will look for build artefacts in Manta.
The default value for this key, as shipped in this repository, is
`"/Joyent_Dev/public/builds"`.  If you wish to include an artefact that
comes from a different Manta directory tree, you may specify the name of
an alternative top-level `build.spec` key on a per-file basis.

For example, Joyent ships firmware files for specific server hardware that are
not available under an opensource license.  As a result, these files are only
included in the commercially supported builds of Triton to Joyent customers.
The firmware artefact is stored in a different (Joyent-private) area of Manta,
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
artefact, rather than the default key of `"manta-base-path"`.

#### Alternative Branch Selection

By default, the build artefacts sourced for inclusion in the headnode
installation media are from the _master_ branch of their respective source
repository.  [Mountain Gorilla][mg] includes the branch in names of
the build artefact directories and files.

The default branch may be overridden by specifying the `"bits-branch"` key.
The build branch for an individual zone or file may be overriden by specifying
`"branch"` in the artefact definition.  For example, to obtain artefacts from
the `release-20150514` branch for everything except the platform (and platform
boot tarball) and cnapi zone, the following could be used in
`build.spec.local`:

```
{
    "bits-branch": "release-20150514",
    "zones": {
        "cnapi": {"branch": "master"}
    }
    "files": {
        "platform": { "branch": "master" },
        "platboot": { "branch": "master" },
        "platimages": { "branch": "master" }
    }
}
```

As a convenience, the build will run `bin/convert-configure-branches.js` to
convert `configure-branches` if it exists to a `build.spec.branches` file.
This allows users to supply simple `component` and `branch` data in an simpler
format. The above `build.spec.local` fragment would be written:

```
bits-branch: release-20150514
cnapi: master
platform: master
```

Note here, that since the `platform`, `platboot` and `platimages` artifacts
and the `agents` and `agents_md5` artifacts should always be matched. The
tool that writes `build.spec.local` will include complementary values
automatically. Any keys that do not map directly to a component (for example,
`bits-branch` in the above snippet) are taken as top-level keys for the
`build.spec.branches` file assuming that they're valid `build.spec` keys.

Note the build will merge `build.spec`, `build.spec.local` and
`build.spec.branches` in that order into a file called `build.spec.merged`
and will **not** report conflicting values across `build.spec.*` files.

#### Alternative build timestamp selection

By default, the build artifacts used for inclusion in the headnode
installation from a given branch are obtained from a file named following
the pattern `buildjob-latest`, which points to a manta directory named using
`buildjob-build_timestamp`. Sometimes it is desirable to pick a different
image than the most recently created one. On these cases, it's possible
to specify the `build_timestamp` in `build.spec.local`:

```
{
    "files": {
        "platform": {
            "branch": "master",
            "build_timestamp": "20181024T220414Z"
        },
        "sdcadm": {
            "branch": "rfd67",
            "build_timestamp": "20171030T214543Z"
        }
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
sets of build artefacts, depending on the type of build.

#### Conditional Artefact Inclusion

Through the definition and activation of [Features](#feature-definition) via
the `"features"` key in the build specification, particular subsets of build
artefacts may be included or excluded.

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

The `"if_not_feature"` directive causes the `"platform"` build artefact to be
downloaded if, and only if, the `"debug-platform"` feature is disabled for this
build.  Conversely, the `"if_feature"` directive causes the `"platform-debug"`
artefact to become active when a DEBUG build is requested.  In this way, a
selection between two different build artefacts may be made based on features.
Feature activation is subsequently queried during later phases of the build
through the use of the `--feature` (`-f`) flag to `bin/buildspec`.

### Automating Headnode Setup: `answers.json`

The setup answers file, `answers.json`, provides information required for
headnode setup that would otherwise need to be entered by the user into the
interactive installer.  Particularly for local development work, it can be
convenient to specify some, or all, of this information in advance.  The
`answers.json.tmpl` and `answers.json.tmpl.external` files provide usable
examples for local development; the former configures only the admin network on
setup, the latter configures an external network as well.

The inclusion of a setup answers file in the resultant installation media is
controlled by the `"answer-file"` key in the build specification.

### Debugging build failures

Build logs are located in `sdc-headnode/log/build.log.TIMESTAMP`, and the logs
of the latest *successful* build are symlinked at `sdc-headnode/log/latest`.

Setting `TRACE=true` in the environment will produce verbose output from
`bash`.  If you are using `bash` version 4.1 or later, you can combine `TRACE`
with these environment variables for finer-grained control over trace output:

- `TRACE_LOG`: send trace output to this file instead of `stderr`.
- `TRACE_FD`: send trace output to this file descriptor instead of `stderr`.
  Note that the passed file descriptor must be opened in the process that
  will fork to invoke the shell script.

The build scripts also install an `ERR` trap handler that should emit a simple
shell stack trace on failure, even when tracing is not enabled.

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
  - mount the usbkey (if required) using `sdc-usbkey mount`
  - copy your modifications over the existing scripts
  - run `sdc-factoryreset` to re-run the setup process

<!-- References -->

[mg]: https://github.com/joyent/mountain-gorilla
[manta]: https://github.com/joyent/manta
[buildspec]: #build-specification-buildspec-and-buildspeclocal
[autosetup]: #automating-headnode-setup-answersjson
[coal-setup.md]: https://github.com/joyent/triton/blob/master/docs/developer-guide/coal-setup.md
