# SDC Upgrade Scripts

These scripts will be used for the JPC upgrades on June 5th.  There's a fair bit
of work to do to make them sufficiently general.

Get the latest upgrade scripts to the target HN, including the 'zones' tree
copy for 'upgrade-setup.sh'. For example:

    ln -s .../usb-headnode/zones zones
    rsync -akv ../upgrade/ beta4:/var/tmp/tmick/upgrade/

To run an upgrade:

    # become root
    p su -

    ./version-list.sh > rollback-images
    ./get-latest.sh > upgrade-images
    ./download-all.sh upgrade-images 2>&1 | tee download.out
    cp -r /usbkey/extra ./oldzones
    ./upgrade-setup.sh 2>&1 | tee setup.out
    # Add new services if required:
    # ./add-sdc.sh
    ./upgrade-all.sh upgrade-images 2>&1 | tee upgrade.out

To rollback:

    mv zones newzones
    mv oldzones zones
    ./upgrade-setup.sh 2>&1 | tee rollback-setup.out
    ./upgrade-all rollback-images 2>&1 | tee rollback.out

To make a changelog:

    ./get-changes.sh upgrade-images.sh > changelog.sh

    # changelog.sh is a script that assumes it runs in a directory where
    # all the relevant service repos are present in subdirectories named
    # identically to their role. E.g., cloning CA creates 'cloud-analytics'
    # by default; it would need to be renamed to 'ca' for this script.




# Trent's Notes (ignore for now)

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

