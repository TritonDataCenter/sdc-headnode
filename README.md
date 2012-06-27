# USB headnode

This is the main repo for building USB headnode images for SmartDataCenter.

- repo: <git@git.joyent.com:usb-headnode.git>
- browsing: <https://mo.joyent.com/usb-headnode>
- bugs/issues: <https://devhub.joyent.com/jira/browse/HEAD>



# Building

There are four main build outputs from this repo:

- `./bin/build-image <tar|usb|coal>`: wrapper around other tools 
- `./bin/build-tar-image`: outputs a tarball boot-<branch/buildstamp>.tgz
- `./bin/build-usb-image boot-*.tgz`: outputs a usb tarball 
  usb-<branch/buildstamp>-4gb.tgz
- `./bin/build-upgrade-image boot-*.tgz`: outputs an upgrade tarball 
  upgrade-<branch/buildstamp>.tgz
- `./bin/build-coal-image usb-*.tgz`: outputs a coal tarball
  coal-<branch/buildstamp>.tgz

If you are just developing on your Mac, you probably want:

    make coal

and occasionally:

    make sandwich


# Build Prerequisites

You can build usb-headnode either on your Mac or on a SmartOS zone.

Mac setup:

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

- Create a dev zone on one of the "bh1-build*" boxes (I've used bh1-build0)
  and set it up as per
  <https://hub.joyent.com/wiki/display/dev/Building+the+SmartOS+live+image+in+a+SmartOS+zone#BuildingtheSmartOSliveimageinaSmartOSzone-HiddenWIPinstructionsfromJoshforsettingthisuponbh1build2>.

  Currently, you need to follow the steps all the way to running "./configure"
  in the illumos-live clone. This updates your system as required for
  building the platform -- some of which is also required for building
  usb-headnode.

- You need nodejs >=0.4.9 and npm 1.x installed and on your path. Here is one
  way to do it:

        pkgin -y in nodejs-0.4.9
        curl http://npmjs.org/install.sh | sh

  WARNING: Installing npm 1.x into /opt/local like this collides with the
  npm 0.2.x from pkgsrc. Agents builds like CA and the agents.git repos
  require npm 0.2.x first on the PATH, so if you plan to build those
  as well, then you can follow the layout used by MG builds
  (see <https://mo.joyent.com/mountain-gorilla/blob/master/README.md>)
  which is to install npm 1.x in "$HOME/opt/npm":

        pkgin -y in nodejs-0.4.9
        mkdir -p $HOME/opt/npm
        curl http://npmjs.org/install.sh | npm_config_prefix=$HOME/opt/npm clean=no sh

  then if you want that one to be the default:

        npm config set prefix $HOME/opt/npm
        cat >> $HOME/.bashrc <<ADDNPM
        export PATH=$HOME/opt
        ADDNPM



# Configuration

This is optional. Without any configuration of your usb-headnode build you'll
get a reasonable build, but there are a number of knobs you can turn. The
most interesting/helpful ones are:

- Add your public ssh key to "config/config.coal.inc/root.authorized_keys".
  This file will get used for the root user so you can ssh into your running
  VM.

- You can override keys in "build.spec" with a "build.spec.local" file.
  Popular "build.spec.local" keys are (obviously you have to remove
  the comments):

        {
          // Don't bother tar'ing up the vmware image.
          "build-tgz": "false",

          // Give your VMWare VM 3400 MiB (or whatever you want) instead of
          // the default 2816 MiB.
          "coal-memsize": 3400
        }

# Re-building a single zone


1.  Build the filesystem tarball for the zone:

    This process has changed and will be updated soon with new instructions. The
    short answer is that you should use MG to build the fs.tar.bz2 now.

2.  Copy in the fs tarball:

        ssh root@10.99.99.7 /usbkey/scripts/mount-usb.sh
        scp zones/mapi/fs.tar.bz2 root@10.99.99.7:/mnt/usbkey/zones/mapi/fs.tar.bz2
        scp zones/mapi/fs.tar.bz2 root@10.99.99.7:/usbkey/zones/mapi/fs.tar.bz2

    Note, we copy it into both the USB key (necessary to be there for
    reboot) and into the usbkey copy (in case you re-create the zone
    without a reboot).

3.  Recreate the zone:

        ssh -A root@10.99.99.7 'vmadm destroy $(vmadm lookup alias=mapi)'
        ssh -A root@10.99.99.7 /usbkey/scripts/headnode.sh

Warning: In general this requires your changes to be locally commited
(tho not pushed). HEAD-465 added support for uncommited changes for
MAPI_DIR, but not for the others.

