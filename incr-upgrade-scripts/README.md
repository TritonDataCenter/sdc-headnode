# SDC (Incremental) Upgrade Scripts

These scripts can be used to drive incremental upgrades of SDC 7 (as opposed
to usb-headnode.git/bin/upgrade.sh which is about the major SDC 6.5 -> 7 upgrade).
See HEAD-1795 for intended improvements to this process.

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

Get backup copies of /usbkey/... sections and tools in case of rollback:

    cp -r /usbkey/extra ./oldzones
    cp -r /usbkey/default ./olddefault
    cp -r /usbkey/scripts ./oldscripts

    cp -rP /opt/smartdc/bin ./oldtools



## upgrade zone: amon, sdc, napi, dapi, imgapi, fwapi, papi, cloudapi, ca, vmapi, cnapi, adminui


The general procedure is:

    ./upgrade-setup.sh upgrade-images 2>&1 | tee setup.out

    # Add new roles if required, e.g.:
    #  ./add-FOO.sh
    # Currently this applies to 'amonredis', 'sdc' and 'papi' if you
    # don't yet have them.

    # Upgrade tools in the GZ (in /opt/smartdc/bin).
    ./upgrade-tools.sh 2>&1 | tee tools.out

    # Upgrade the zones.
    ./upgrade-all.sh upgrade-images 2>&1 | tee upgrade.out



To rollback:

    # WARNING: The 'rollback-images' generated above currently includes *all*
    # roles. Not just the ones you've upgraded. Generally that is fine, the
    # rollback will be a no-op, but you might want to edit this file first
    # to *just* include the zones in 'upgrade-images'.

    mv zones newzones
    mv oldzones zones
    mv default newdefault
    mv olddefault default
    mv scripts newscripts
    mv oldscripts scripts
    ./upgrade-setup.sh rollback-images 2>&1 | tee rollback-setup.out

    mv tools newtools
    mv oldtools tools
    ./upgrade-tools.sh 2>&1 | tee rollback-tools.out

    ./upgrade-all.sh rollback-images 2>&1 | tee rollback.out


TODO: move this up
Special follow up notes for 'ufds':

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



TODO: move this up
## 'sapi' upgrade

    # If upgrading sapi:
    #
    # IMPORTANT: if this is the first upgrade to SAPI since HEAD-1804 changes
    # you'll also need to edit:
    #
    #  /opt/smartdc/sapi/lib/server/attributes.js
    #
    # in the SAPI zone and add 'SAPI_MODE' to the allowed_keys in
    # sanitizeMetadata() and restart the sapi service.
    #
    ./upgrade-sapi.sh upgrade-images 2>&1 | tee upgrade-sapi.out



## upgrade zone: redis, amonredis

TODO


## upgrade zone: sapi

TODO


## upgrade zone: ufds

TODO: upgrade-ufds.sh, rollback-ufds.sh


## upgrade zone: rabbitmq

TODO: upgrade-rabbitmq.sh


## upgrade zone: assets, dhcpd

TODO


## upgrade zone: binder, manatee (MORAY-138)

TODO: this is MORAY-138, talk to matt


## upgrade zone: manatee (*after* MORAY-138)

TODO

## Upgrading all agents

First the 6.5 agents. Download the latest "agentsshar-upgrade" build
from <https://bits.joyent.us/builds/agentsshar-upgrade/master-latest/agentsshar-upgrade/>
then move it to a file named "agents65.sh" (as required by the upgrade script).

    /usbkey/scripts/update_agents agents65.sh

The SDC7 agents. Download the latest "agentsshar" build
from <https://bits.joyent.us/builds/agentsshar/master-latest/agentsshar/>.

    /usbkey/scripts/update_agents agents-master-DATE-gSHA.sh


## Upgrading just a specific agent

TODO: describe editing the agentsshar manually



## To make a changelog:

    ./get-changes.sh upgrade-images.sh > changelog.sh

    # changelog.sh is a script that assumes it runs in a directory where
    # all the relevant service repos are present in subdirectories named
    # identically to their role. E.g., cloning CA creates 'cloud-analytics'
    # by default; it would need to be renamed to 'ca' for this script.



## Future improvements

- Should we `dc-maint-{start,end}.sh` for provision pipeline upgrades?
  I.e. for napi, dapi, imgapi, fwapi, papi, vmapi, cnapi.

- We need an LB in front of cloudapi to maint-window it.
