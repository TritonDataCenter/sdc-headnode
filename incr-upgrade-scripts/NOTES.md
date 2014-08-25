<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2014, Joyent, Inc.
-->

# Some notes from Trent which you can ignore now

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

-   Rollback if necessary.

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
