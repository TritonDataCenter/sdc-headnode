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

- Add your public ssh key to "config/config.inc/root.authorized_keys".
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

# Adding a new service:

Important files, see README.zones for more details:

/zones/$SERVICE/setup      - required
/zones/$SERVICE/configure  - required

/sapi/config/services/$SERVICE/service.json - required

 - SAPI manifests
Manifests should exist in the image, typically at
/opt/smartdc/$SERVICE/sapi_manifests, and that directory (or directories)
should be specified in the setup file before setup.common is sourced, in the
env var similar to this:
CONFIG_AGENT_LOCAL_MANIFESTS_DIRS=/opt/smartdc/$SERVICE

The structure of that directory assumes the following:
/opt/smartdc/$SERVICE/sapi_manifests/$MANIFEST_NAME
  Where each $MANIFEST_NAME has two files:
$MANIFEST_NAME/manifest.json
$MANIFEST_NAME/template

See SAPI docs at https://mo.joyent.com/docs/sapi/master/ and examples COAL for
more information on these files.

# Using specific images

# Re-building a single zone

to be updated - pending SAPI-80, others.

# Testing upgrade

1. Download 6.5.5: <https://stuff.joyent.us/releases/6.5.5/>
   You want the coal-*.tgz package if it wasn't obvious.

2. Open that in VMWare. Let is setup. Create a VMWare snapshot of that
   to fallback to.

3. Make an upgrade package.  Get the latest usb-headnode ("master"
   branch). Then run `make boot upgrade` to build an upgrade-*.tgz.

4. Get that to your coal:   scp upgrade-*.tgz coal:/var/tmp

5. Upgrade:

        ssh coal
        /usbkey/scripts/perform-upgrade.sh /var/tmp/upgrade-*.tgz

6. Watch progress in (a) the console and (b) files in /var/upgrade_*
   (This is a directory with all the logs and dump files. The dir name
   changes depending on the upgrade phase.)

If you are working on the upgrade process, the main relevant files on
bin/upgrade.sh, bin/upgrade_hooks.sh, bin/\* (a number of othre files)
in usb-headnode.git.
