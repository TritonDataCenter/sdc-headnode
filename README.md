This is the main repo for building USB headnode images for SmartDataCenter.

- repo: git@git.joyent.com:usb-headnode.git
- bugs/issues: https://devhub.joyent.com/jira/browse/HEAD

There are two main build outputs from this repo: a VMWare image (called
COAL -- Cloud On A Laptop) used for local development on a Mac; and a
USB key image used for staging and production.


# Building COAL

Prerequisites: A Mac with MacFUSE, Xcode, and VMWare Fusion installed.


Setup: Run VMWare at least once, then run the following to setup VMWare
networking required for COAL:

    ./coal/coal-vmware-setup


Configuration (optional): Without any configuration you'll get a reasonable
build, but there are a number of knobs you can turn. The primary three
things are:

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


Build:

    ./bin/build-image


This should create a "coal-develop-20110616T203554Z-2gb.vmwarevm" (or
"coal-develop-20110616T203554Z-2gb.vmwarevm.tgz" if "build-tgz" is true).
Run that to startup COAL.


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

