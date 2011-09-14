This is the main repo for building USB headnode images for SmartDataCenter.

- repo: git@git.joyent.com:usb-headnode.git
- bugs/issues: https://devhub.joyent.com/jira/browse/HEAD

There are five main build outputs from this repo:

- `make coal`: a VMWare image (called COAL -- Cloud On A Laptop) used for local
  development on a Mac
- `make usb`: a USB key image used for staging and production
- `make upgrade`: a SDC upgrade package
- `make tar`: (aka the "boot-*.tgz" package) a tarball of roughly what is included
  in the 'usb' package. This can be convenient for updating an existing USB
  key with the latest build bits.
- `make sandwich`


# Build Prerequisites

You can build usb-headnode either on your Mac or on a SmartOS zone.

Mac setup:

- Install MacFUSE.

- Install Xcode (not sure about versions now).

- Install VMWare Fusion. Run VMWare Fusion at least once (to create some
  first time config files). Then shut it down and run the following to setup
  VMWare networking required for COAL:

    ./coal/coal-vmware-setup

- You need nodejs >=0.4.9 and npm 1.x installed and on your path. I typically
  build my own something like this:

    # Nodejs build.
    mkdir ~/opt ~/src
    cd ~/src
    git clone -b v0.4.11 git@github.com:joyent/node.git
    cd node
    ./configure --prefix=$HOME/opt/node-0.4.11 && make && make install
    export PATH=$HOME/opt/node-0.4.11:$PATH  # <--- put this in ~/.bashrc

    # npm install
    curl http://npmjs.org/install.sh | sh


SmartOS setup:

- Get VPN access to BH-1. Presumably you want to do this on hardware, and the
  best current place for that is in the Joyent Development Lab in Bellingham,
  aka BH-1 (see <https://hub.joyent.com/wiki/display/dev/Development+Lab>).

- Create a dev zone on one of the "bh1-build*" boxes and set it up as per
  <https://hub.joyent.com/wiki/display/dev/Building+the+SmartOS+live+image+in+a+SmartOS+zone#BuildingtheSmartOSliveimageinaSmartOSzone-HiddenWIPinstructionsfromJoshforsettingthisuponbh1build2>.

  Currently, you need to follow the steps all the way to running "./configure"
  in the illumos-live clone. This updates your system as required for
  building the platform -- some of which is also required for building
  usb-headnode.

- You need nodejs >=0.4.9 and npm 1.x installed and on your path. Here is one
  way to do it:

    pkgin -y in nodejs-0.4.9
    curl http://npmjs.org/install.sh | sh

See Trent's full attempt notes here: <https://gist.github.com/4e3a9ea4b467cb1cef6a>


# Configuration

This is optional. Without any configuration of your usb-headnode build you'll
get a reasonable build, but there are a number of knobs you can turn. The
primary three things are:

1. Add your public ssh key to "config/config.coal.inc/root.authorized_keys".
   This file will get used for the root user so you can ssh into your running
   VM.

2. You can override keys in "build.spec" with a "build.spec.local" file. A
   popular "build.spec.local" is:

        {
          "build-tgz": "false",
          "use-proxy": "true"
        }

    "use-proxy" will use a local file download proxy (if available) to
    speed up downloads for your build.

3. You can have a "config/config.coal.local" file which is a complete
   override of "config/config.coal" if you want to tweak any of those
   variables.


# Build

As noted above the main targets are:

    make coal    # default target
    make usb
    make upgrade
    make tar

These are all shims for the primary build script:

    ./bin/build-image [TARGET]


`make coal` should create a "coal-develop-20110616T203554Z-2gb.vmwarevm" (or
"coal-develop-20110616T203554Z-2gb.vmwarevm.tgz" if "build-tgz" is true).
Open that to startup COAL.


# Building a zone using a local clone

Sometimes you want to build COAL using changes in a local clone. Here is how
for the "mapi" zone:

    MAPI_DIR=`pwd`/../mcp_api_gateway ./bin/build-image

Likewise for the others zones using these envvars:

    ADMINUI_DIR
    CAPI_DIR
    BOOTER_DIR
    MAPI_DIR
    PORTAL_DIR
    PUBAPI_DIR
    CLOUDAPI_DIR
    BILLAPI_DIR



# Re-building a single zone

A full rebuild and restart of COAL takes a while... and may destroy state
that you have in your COAL. You can rebuild and update a particular zone
from a local working copy as follows (using the "mapi" zone as an example):

1.  Build the filesystem tarball for the zone:

        MAPI_DIR=`pwd`/../mcp_api_gateway ./bin/build-fstar mapi

    This will just build a "mapi.tar.bz2".

2.  Copy in the fs tarball:

        ssh root@10.99.99.7 /usbkey/scripts/mount-usb.sh
        scp mapi.tar.bz2 root@10.99.99.7:/mnt/usbkey/zones/mapi/fs.tar.bz2
        scp mapi.tar.bz2 root@10.99.99.7:/usbkey/zones/mapi/fs.tar.bz2

    Note, we copy it into both the USB key (necessary to be there for
    reboot) and into the usbkey copy (in case you re-create the zone
    without a reboot).

3.  Recreate the zone:

        ssh -A root@10.99.99.7 /usbkey/scripts/destroy-zone.sh mapi
        ssh -A root@10.99.99.7 /usbkey/scripts/create-zone.sh mapi -w

Warning: In general this requires your changes to be locally commited
(tho not pushed). HEAD-465 added support for uncommited changes for
MAPI_DIR, but not for the others.

Likewise for the others zones using these envvars:

    ADMINUI_DIR
    CAPI_DIR
    BOOTER_DIR
    MAPI_DIR
    PORTAL_DIR
    PUBAPI_DIR
    CLOUDAPI_DIR
