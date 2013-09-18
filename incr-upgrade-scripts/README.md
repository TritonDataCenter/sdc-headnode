# SDC (Incremental) Upgrade Scripts

These scripts can be used to drive incremental upgrades of SDC 7 (as opposed
to usb-headnode.git/bin/upgrade.sh which is about the major SDC 6.5 -> 7 upgrade).
See HEAD-1795 for intended improvements to this process.

## To run an upgrade

    # Get the latest 'incr-upgrade' package
    wget https://bits.joyent.us/builds/incr-upgrade/master-latest/incr-upgrade/incr-upgrade-VERSION.tgz --no-check-certificate --user=guest --password=XXX
    tar xf incr-upgrade-VERSION.tgz
    cd incr-upgrade-VERSION

    # become root
    p su -

    ./version-list.sh > rollback-images

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

    # Pre-download all the images to be used if you like. If you skip this,
    # it'll be lazily done by 'upgrade-all.sh'.
    ./download-all.sh upgrade-images 2>&1 | tee download.out

    cp -r /usbkey/extra ./oldzones
    cp -r /usbkey/default ./olddefault
    cp -r /usbkey/scripts ./oldscripts
    ./upgrade-setup.sh upgrade-images 2>&1 | tee setup.out

    # Add new roles if required, e.g.:
    ./add-sdc.sh

    cp -rP /opt/smartdc/bin ./oldtools
    ./upgrade-tools.sh 2>&1 | tee tools.out
    ./upgrade-all.sh upgrade-images 2>&1 | tee upgrade.out

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

To rollback:

    mv zones newzones
    mv oldzones zones
    mv default newdefault
    mv olddefault default
    mv scripts newscripts
    mv oldscripts scripts
    ./upgrade-setup.sh 2>&1 | tee rollback-setup.out

    mv tools newtools
    mv oldtools tools
    ./upgrade-tools.sh 2>&1 | tee rollback-tools.out

    ./upgrade-all rollback-images 2>&1 | tee rollback.out

To make a changelog:

    ./get-changes.sh upgrade-images.sh > changelog.sh

    # changelog.sh is a script that assumes it runs in a directory where
    # all the relevant service repos are present in subdirectories named
    # identically to their role. E.g., cloning CA creates 'cloud-analytics'
    # by default; it would need to be renamed to 'ca' for this script.


## Trent's Notes (ignore for now)

A possible new flow here, using a JSON spec file for to upgrade.

-   Write a upgrade spec JSON file

        $ cat foo.json   # should have a meaningful name, this is the "foo" upgrade
        {
            "imgapi": "4803c1cd-5882-9c48-bc2a-fc81c1429a89",
            "adminui": "latest"
        }

    Note: This doesn't capture agents, platforms.

-   Fill in the 'latest' markers in there. That is done lazily and cached
    to ${specfile}.1

-   Prepare. Still presuming only one instance of each service
    considered.

        $ ./prepare.sh foo.json
        ... make a clean fresh /var/tmp/upgrade-foo dir (or perhaps require it to be clean)
        ... bail if we have two instances of any of the services listed
        ... gets the current image for current instance of each image
        Wrote '/var/tmp/upgrade-foo/rollback.json'
        ... fills in "latest" markers in the spec file
        ... order the images to be upgraded (hardcoded list of bottom stack to top)
        Wrote '/var/tmp/upgrade-foo/spec.json'

-   Get the images.

        $ ./download-images.sh foo[.json]
        ... get each image in '/var/tmp/upgrade-foo/spec.json' into IMGAPI if necessary

-   Upgrade

        $ ./upgrade.sh foo[.json]
        ... perhaps bail if not healthy, or at least note starting healthcheck state
        ... confirmation of what is going to be done
        ... upgrade-setup and upgrade-zone for each service in order from spec.json
        ... pause after each zone

-   Rollback if necessary. Rollback /usbkey/extra bits have been saves in
    '/var/tmp/upgrade-foo'.

        # Optionally can just roll back a particular service.
        $ ./rollback.sh foo[.json] [<service> ...]
        ... confirmation
        ... rollback-setup and rollback-zone for each service in spec.json
            backwards

This should be a package on updates.joyent.com for self-update as first step of upgrade.
The usb-headnode/{tools,default,zones,config} should be a "gzbits" (or
whatever) release tarball and used to update bits in the headnode GZ (and perhaps on CNs?)
as part of the upgrade.

Should grab logs from the old zone before reprovision. Should perhaps snapshot and send
to a file before reprovision.

Reprovision of each zone should be followed up by waiting for setup_complete...
and timeout on that (as headnode.sh).
