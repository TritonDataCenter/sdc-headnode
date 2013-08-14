# SDC Upgrade Scripts

These scripts will be used for the JPC upgrades on June 5th.  There's a fair bit
of work to do to make them sufficiently general.

To run an upgrade:

    # become root
    p su -

    ./version-list.sh > rollback-images
    ./get-latest.sh > upgrade-images
    ./download-all.sh upgrade-images 2>&1 | tee download.out
    cp -r /usbkey/extra ./oldzones
    ./upgrade-setup.sh 2>&1 | tee setup.out
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

