# SDC (Incremental) Upgrade Scripts

These scripts can be used to drive incremental upgrades of SDC 7 (as opposed
to usb-headnode.git/bin/upgrade.sh which is about the major SDC 6.5 -> 7 upgrade).
See HEAD-1795 for intended improvements to this process.



## A note for ancient SDC7's

You have an "ancient" SDC7 install if any of the following are true:

- You don't have an 'amonredis' zone, i.e. `vmadm list | grep amonredis` on
  the HN GZ is empty.
- You don't have an 'sdc' zone, i.e. `vmadm list | grep sdc` on the HN GZ is
  empty.

If you have an ancient SDC7, then the following instructions have pitfalls.
You need to speak with Trent Mick or others knowing SDC incr-upgrades to
proceed.


## Prepare for upgrades (all zones)

Get the latest 'incr-upgrade' package

Where you have the node-manta client tools:

    latest=$(mls /Joyent_Dev/stor/builds/incr-upgrade | grep 'master-2' | sort | tail -1)
    pkg=$(mls /Joyent_Dev/stor/builds/incr-upgrade/$latest/incr-upgrade | grep tgz)
    mget -O /Joyent_Dev/stor/builds/incr-upgrade/$latest/incr-upgrade/$pkg
    scp $pkg us-beta-4:/var/tmp

Then crack it in the your working dir on the GZ:

    ssh us-beta-4
    cd /var/tmp
    tar xf incr-upgrade-VERSION.tgz
    cd incr-upgrade-VERSION

Become root if not already:

    p su -

Capture current image versions in case we need to rollback.

    ./version-list.sh > rollback-images

Specify the roles and images that will be upgraded in "upgrade-images" file:

    # Either get a list of the latest versions of all roles via
    #       ./get-latest.sh > upgrade-images
    # or manually create such a list with relevant roles and specific
    # image UUIDs in the format:
    #       export ${ROLE}_IMAGE=$UUID
    #       ...
    # e.g.:
    #       export IMGAPI_IMAGE=99bb26b5-cd93-9447-a1d0-70191d78690b
    #       export VMAPI_IMAGE=f9b40a06-7e87-3b4d-832a-faf38eb34506
    vi upgrade-images

Pre-download all the images to be used if you like. If you skip this,
it'll be lazily done by 'upgrade-all.sh'.

    ./download-all.sh upgrade-images 2>&1 | tee download.out

Update GZ tools (in /opt/smartdc/bin) and headnode scripts (in /usbkey/scripts)
and zone defaults (/usbkey/default).
WARNING: If you don't have an "sdc" zone (see "ancient" notes section above),
then you cannot run this step until you've added it.

    cp -r /usbkey/default ./olddefault
    cp -r /usbkey/scripts ./oldscripts
    cp -rP /opt/smartdc/bin ./oldtools
    ./upgrade-tools.sh 2>&1 | tee tools.out




## Upgrading all agents

Getting the latest agentsshar:

    latest=$(mls /Joyent_Dev/stor/builds/agentsshar | grep 'master-2' | sort | tail -1)
    pkg=$(mls /Joyent_Dev/stor/builds/agentsshar/$latest/agentsshar | grep '\.sh$')
    mget -O /Joyent_Dev/stor/builds/agentsshar/$latest/agentsshar/$pkg
    scp $pkg us-beta-4:/var/tmp

First the 6.5 agents. Download the latest "agentsshar-upgrade" build
from <https://bits.joyent.us/builds/agentsshar-upgrade/master-latest/agentsshar-upgrade/>
then move it to a file named "agents65.sh" (as required by the upgrade script).

    /usbkey/scripts/update_agents agents65.sh

The SDC7 agents. Download the latest "agentsshar" build
from <https://bits.joyent.us/builds/agentsshar/master-latest/agentsshar/>.

    /usbkey/scripts/update_agents agents-master-DATE-gSHA.sh




## other upgrades

This is a catch-all script that applies other upgrades (typically things
like SAPI service definition tweaks):

    ./upgrade-other.sh 2>&1 | tee other.out



## add new zone: amonredis, sdc, papi

If you don't have one or more of the following zones, then you should add them:

    ./add-sdc.sh 2>&1 | tee sdc.out
    ./add-amonredis.sh 2>&1 | tee amonredis.out
    ./add-papi.sh 2>&1 | tee papi.out

Note: *currently* you can get away without PAPI. That will change with
[PAPI-55](https://devhub.joyent.com/jira/browse/PAPI-55) and
[PAPI-8](https://devhub.joyent.com/jira/browse/PAPI-8).



## put the DC in maint mode (optional)

The DC can be put in "maintenance mode": cloudapi in readonly mode, wait
for workflow to clear finish its current queue of jobs. This is recommended
for upgrades of the following: rabbitmq, ufds.

    ./dc-maint-start.sh



## upgrade zone: rabbitmq

    ./upgrade-rabbitmq.sh upgrade-images 2>&1 | tee rabbitmq.out

To rollback rabbitmq:

    ./rollback-rabbitmq.sh rollback-images 2>&1 | tee rabbitmq-rollback.out



## upgrade zone: ufds

Currently the UFDS upgrade requires that the moray zone on the HN have
a recent "backfill" script. Check that via:

    for uuid in $(vmadm lookup state=running tags.smartdc_role=moray); do zlogin $uuid grep getPredicate /opt/smartdc/moray/node_modules/.bin/backfill >/dev/null && echo Moray zone $uuid is good || echo Moray zone $uuid needs a newer backfill script; done

**Only if you get "Moray zone $uuid needs a newer backfill script"** then run
this (where $moray_uuid is from the previous command):

    cp ./backfill-for-ufds-upgrade /zones/$moray_uuid/root/opt/smartdc/moray/node_modules/moray/bin/backfill

Upgrade:

    ./upgrade-ufds.sh upgrade-images 2>&1 | tee ufds.out

To rollback UFDS:

    ./rollback-ufds.sh rollback-images 2>&1 | tee ufds-rollback.out

TODO: for upgrades of UFDS where the *old* UFDS is already passed all the
index updates... we will be wasting time doing unnecessary backfills. We should
discover that and only backfill as necessary.


## upgrade zone: imgapi

    ./upgrade-imgapi.sh upgrade-images 2>&1 | tee imgapi.out

Also this migration should be run once. It isn't *harmful* to run more than
once, it just involves a number of unnecessary uploads to manta if run
repeatedly for every upgrade:

    sdc-login imgapi 'cd /opt/smartdc/imgapi && /opt/smartdc/imgapi/build/node/bin/node lib/migrations/migration-010-backfill-archive.js'


To rollback (however note that the imgapi migrations don't currently have
rollback support):

    ./rollback-imgapi.sh rollback-images 2>&1 | tee imgapi-rollback.out



## upgrade zone: amon, sdc, napi, dapi, fwapi, papi, cloudapi, ca, vmapi, cnapi, adminui

    ./upgrade-all.sh upgrade-images 2>&1 | tee other-zones.out


To rollback:

    # WARNING: The 'rollback-images' generated above currently includes *all*
    # roles. Not just the ones you've upgraded. Generally that is fine, the
    # rollback will be a no-op, but you might want to edit this file first
    # to *just* include the zones in 'upgrade-images'.

    mv default newdefault
    mv olddefault default
    mv scripts newscripts
    mv oldscripts scripts
    mv tools newtools
    mv oldtools tools
    ./upgrade-tools.sh 2>&1 | tee rollback-tools.out

    ./upgrade-all.sh rollback-images 2>&1 | tee rollback.out



## upgrade zone: redis, amonredis

TODO



## upgrade zone: moray

**Limitation:** Currently this just knows how to upgrade a moray zone on the
headnode. If you have HA moray running on other CNs, this cannot yet upgrade
them.

    ./upgrade-moray.sh upgrade-images 2>&1 | tee moray.out

To rollback moray:

    ./upgrade-moray.sh rollback-images 2>&1 | tee moray-rollback.out



## upgrade zone: sapi

IMPORTANT: If this is upgrade a SAPI that dates from *before*
[HEAD-1804](https://devhub.joyent.com/jira/browse/HEAD-1804) changes (where
setup/boot scripts were moved *into* the images), you'll first need to tweak
the existing old SAPI:

    sdc-login sapi
    vi /opt/smartdc/sapi/lib/server/attributes.js
    # Add 'SAPI_MODE' to the allowed_keys in `sanitizeMetadata()`.
    svcadm restart sapi


Then back in the GZ:

    ./upgrade-sapi.sh upgrade-images 2>&1 | tee upgrade-sapi.out



## upgrade zone: assets, dhcpd

TODO



## upgrade zone: binder, manatee (MORAY-138)

TODO: this is MORAY-138, talk to matt



## upgrade zone: manatee (*after* MORAY-138)

TODO



## Special case: Upgrading just a specific agent

TODO: describe editing the agentsshar manually



## Upgrading a CN platform


TODO


## Upgrading the platform

First you must make the platform available in the DC by (a) downloading it
and (b) running the "install-platform.sh" script on the headnode.
Internally, platforms builds are uploaded to Manta here:

    [manta /Joyent_Dev/stor/builds/platform/master-20140211T152333Z/platform]$ ls
    platform-master-20140211T152333Z.tgz
    ...

Then it is made available to the DC as follows:

    [root@headnode (my-dc) /var/tmp]# /usbkey/scripts/install-platform.sh  ./platform-master-20140211T152333Z.tgz
    ==> Mounting USB key
    ==> Staging 20140211T152333Z
    ######################################################################## 100.0%
    ==> Unpacking 20140211T152333Z to /mnt/usbkey/os
    ==> This may take a while...
    ==> Copying 20140211T152333Z to /usbkey/os
    ==> Unmounting USB Key
    ==> Adding to list of available platforms
    ==> Done!

Then (c) you assign the node in question to boot to the new platform. If the
target node is a compute node (CN) then this is done via CNAPI. For example:

    [root@headnode (my-dc) /var/tmp/tmick/img-mgmt-v2]# sdc-cnapi /boot/00000000-0000-0000-0000-002590943670
    HTTP/1.1 200 OK
    ...
    {
      "platform": "20130111T180733Z",
      "kernel_args": {
        "hostname": "00-25-90-94-36-70",
        "rabbitmq": "guest:guest:10.3.1.23:5672",
        "rabbitmq_dns": "guest:guest:rabbitmq.my-dc.joyent.us:5672"
      },
      "default_console": "vga",
      "serial": "ttyb"
    }

    [root@headnode (my-dc) /var/tmp]# sdc-cnapi /boot/00000000-0000-0000-0000-002590943670 -X POST -d '{"platform": "20131210T060639Z"}'
    HTTP/1.1 204 No Content
    ...

    [root@headnode (my-dc) /var/tmp]# sdc-cnapi /boot/00000000-0000-0000-0000-002590943670
    HTTP/1.1 200 OK
    ...
    {
      "platform": "20131210T060639Z",
      "kernel_args": {
        "hostname": "00-25-90-94-36-70",
        "rabbitmq": "guest:guest:10.3.1.23:5672",
        "rabbitmq_dns": "guest:guest:rabbitmq.my-dc.joyent.us:5672"
      },
      "default_console": "vga",
      "serial": "ttyb"
    }

If the target node is the headnode (HN), then:

    [root@headnode (my-dc) /var/tmp]# /usbkey/scripts/switch-platform.sh 20140211T152333Z
    ...


Then (d) you reboot the platform. Typically you'd want to be watching the
server boot on its console.

    [root@headnode (my-dc) /var/tmp]# sdc-cnapi /servers/00000000-0000-0000-0000-002590943670/reboot -X POST
    HTTP/1.1 202 Accepted
    ...
    {
      "job_uuid": "4351dc6a-dd89-4fd9-9def-cd6b082b2c8b"
    }

or simply

    [root@headnode (my-dc) /var/tmp]# shutdown -y -i6 -g0



## Remove the DC from maint mode

    ./dc-maint-end.sh



## To make a changelog:

    ./get-changes.sh upgrade-images.sh > changelog.sh

    # changelog.sh is a script that assumes it runs in a directory where
    # all the relevant service repos are present in subdirectories named
    # identically to their role. E.g., cloning CA creates 'cloud-analytics'
    # by default; it would need to be renamed to 'ca' for this script.



## Future improvements

- upgrade-ufds.sh should automatically determine what backfilling needs to
  be done. Old notes on this:

        # If you upgraded ufds, it's important that you also backfill missing column
        # data as UFDS does not do this automatically. To do this you'll need to
        # look at:
        #
        # git log -p sapi_manifests/ufds/template
        #
        # in the ufds.git repo to figure out which columns need to be backfilled,
        # then run something like:
        #
        # /opt/smartdc/moray/node_modules/moray/bin]# ./backfill -i name -i version ufds_o_smartdc
        #
        # in the moray zone. See JPC-1302 for some more usage ideas.

- Should we `dc-maint-{start,end}.sh` for provision pipeline upgrades?
  I.e. for napi, dapi, imgapi, fwapi, papi, vmapi, cnapi.

- We need an LB in front of cloudapi to maint-window it.

