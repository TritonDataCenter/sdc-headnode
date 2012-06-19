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

# Upgrade Overview

A lot of issues are discovered during upgrade, these are typically related to 
backup and restore as they are used during the upgrade process). 
The root cause is usually a lack of understanding of how
the upgrade mechanism works or simply an oversight, i.e. not thinking about 
how the change you are making will affect or be applied in an upgrade situation.
This document provides a list of guidelines and examples for everyone to 
follow which will make backup/restore/upgrade a lot more stable.  
Since upgrade basically backs up the zones, deletes them, recreates them, 
then restores them, having stable backup/restore will go a long way toward 
making upgrade more stable as well.  Although each role does have its own 
backup/restore scripts, unfortunately these are all currently fairly inconsistent. 
Having more commonality and simplicity in these scripts will also help make 
things more stable.  Because restore and upgrade are already 
high-stress operations, we need to make these things as reliable as we can.

In addition, because of the way that we do upgrade, its important to
remember that we may be backing up using older code and restoring using
newer code as part of the upgrade process.  Restore needs to be backward
compatible with older backups.  This is another reason for simplicity in the
way that we do backup/restore.

# Upgrade Guidelines

1. The zone should store all of its persistent data under one common place in
the file system.  For example, the adminui zone stores all of its data under
/opt/smartdc/adminui-data which is easy to backup from the global zone.  As
an alternative, more complex zones, such as mapi, should store all of their
persistent data under their "data" ZFS dataset which we can snapshot and
send into a file as a backup.  Mapi makes things more complex than necessary
because it has configuration files outside of this dataset
(/opt/smartdc/node.config/node.config) which require extra code.  This
should be avoided if possible.

2. Backup/restore should not be dependent on parsing a config file inside the
zone to find things to backup. For example, in JPC the cloudapi
configuration has a billing plugin which in not installed in the "plugins"
directory.  Instead, it was installed elsewhere (breaking guideline #1)
and necessitating the parsing of the configuration file for backup to find
it.

3. Backup should not be dependent on the zone running.  For example, we
should not be trying to following symbolic links inside the zone that are
only valid when the zone is booted.  Mapi is an example of a zone that does
something it would be better to avoid. It has /opt/smartdc/mapi/config as a
symlink to /opt/smartdc/mapi-data/config.  That symlink is both invalid from
the global zone and only points to something inside the zone when the zone
is running.  The mapi backup script can work around this by accessing the
mapi-data hierarchy directly, but it is simpler to avoid this sort of thing,
especially if another engineer who does not know all of the details of the
zone has to work on this.  We should not have to zlogin to the zone to run
something to get a good backup.  While we can do this (e.g. when we dump the
mapi DB), the zone should be stable when it is shutdown and all persistent
data should be in the directory or directories that will be backed up using #1 
above.  If the zone's backup does want to zlogin, the code must
gracefully handle the case where zlogin fails because the zone is halted.
This should not be considered an error.

4. If you are changing configuration or other ways that a zone can be
customized, you need to ensure that the restore code will do the right
thing if it gets a backup that was made on an older version of the zone.
While this is mostly going to occur due to an upgrade, in theory the
customer would need this behavior any time they restore an older backup.

The backup/restore scripts are currently in pretty good shape, although
some of them could still benefit from further simplification.  Going forward,
it will be best if each team takes full responsibility for ensuring that their
backup/restore works properly, both as part of sdc-backup/sdc-restore, and
as part of upgrade.  I'll work on a wiki page that everyone can use as a
checklist and summary of these guidelines to make it easier for each team
to test these things going forward.

