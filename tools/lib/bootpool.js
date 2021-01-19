/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2021 Joyent, Inc.
 */

var mod_child = require('child_process');
/* var mod_child = require('fs'); */

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var lib_common = require('../lib/common');
var lib_oscmds = require('../lib/oscmds');
var lib_usbkey = require('../lib/usbkey');

var VError = mod_verror.VError;
var dprintf = lib_common.dprintf;

/*
 * Figure out if we've booted from a ZFS pool, and make note of which
 * one it is.
 */
function
triton_bootpool(callback)
{
    mod_assert.func(callback, 'callback');

    mod_child.exec(
        '/usr/bin/bootparams | awk -F= \'/^triton_bootpool=/ { print $2}\'', {
            env: lib_oscmds.make_env()
        }, function findbp(err, stdout, stderr) {
            if (err) {
                /* If this happens, we have bigger problems. */
                callback(new VError(err, 'could not sync: %s', stderr.trim()));
                return;
            }

            callback(null, stdout.trim());
        });
}

function
get_bootfs_mount_status(mountpoint, callback)
{
    var status = {
        mountpoint: null,       /* Will be filled in if successful. */
        device: null,           /* Will be filled in if successful. */
        version: null,          /* Will be filled in if successful. */
        options: null,          /* Will be filled in if successful. */
        steps: {                /* Will be filled in if successful. */
            mounted: false,
            options_ok: false,
            marker_file: false
        },
        ok: false,
        message: 'not mounted'
    };

    dprintf('fetching pool mount status for "%s"\n', mountpoint);

    lib_usbkey.get_mount_info(mountpoint, function mnttab_info(err, mi) {
        if (err) {
            callback(new VError(err, 'could not inspect mounted filesystems'),
                    status);
            return;
        }

        /*
         * Okay, convert our mount information into a JSON object like the
         * USB one.  Version is always '2' (loader) for ZFS pool boots.
         * "device" will be the bootfs.
         */

        if (mi === false) {
            dprintf('ok, bootfs says nothing is not mounted.\n');
            callback(null, status);
            return;
        }

        mod_assert.strictEqual(mi.mi_mountpoint, mountpoint);
        status.mountpoint = mountpoint;
        status.device = mi.mi_special;
        if (mi.mi_fstype === 'lofs') {
            /* AHA! We're probably good! */
            status.version = 2; /* Actually consumed by Triton components! */
            status.options = {}; /* Filled in as an empty list. */
            status.steps.mounted = true;
            status.steps.options_ok = true;
            /* NOTE: marker filled in below. */
            status.ok = true;
            status.message = 'mounted';
        } else {
            status.message = 'Something not lofs-mounted on ' + mountpoint;
        }

        /*
         * Set marker file attribute regardless of correct or not so
         * we can avoid callback indentation hell.
         */
        lib_usbkey.check_for_marker_file(mountpoint, function (err, marker) {
            if (err) {
                    callback(new VError(err, 'failed to locate marker on "%s"',
                        mountpoint));
                    return;
            }

            status.steps.marker_file = marker;
            callback(null, status);
        });
    });
}

/*
 * Mount bootfs onto the default mountpoint.
 */
function
ensure_bootfs_mounted(poolname, callback)
{
    var args = [];
    var mountpoint;

    mod_assert.func(callback, 'callback');
    mod_assert.string(poolname, 'poolname');

    dprintf('ensuring bootfs is mounted (no altmountopts for bootfs)...\n');

    args.push('list');
    args.push('-Ho');
    args.push('bootfs');
    args.push(poolname);
    mod_child.execFile('zpool', args, function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'Cannot find bootfs for %s', poolname),
                     '');
            return;
        }

        lib_usbkey.get_mountpoints(function (err, mtpts) {
            if (err) {
                callback(new VError(err, 'could not read mount configuration'));
                return;
            }

            /* Only use default mountpoints. */
            mountpoint = mtpts[0];

            /* Make sure the mountpoint is there. */
            lib_usbkey.ensure_mountpoint_exists(mountpoint, function (err) {
                if (err) {
                    callback(err, '');
                    return;
                }
                var bootfs = '/' + stdout.trim();
                /* Check for /pool/boot standard? */
                if (bootfs !== '/' + poolname + '/boot') {
                    dprintf('HEADS UP: bootfs %s is not SmartOS-standard.\n');
                }

                /*
                 * See if anything is mounted in mountpoint already, and
                 * umount it.
                 */
                dprintf('fetching pool mount ensure information for "%s"\n',
                        mountpoint);

                function do_lofs_mount(bootfs, mountpoint, callback) {
                    /* Okay, let's lofs-mount bootfs on to mountpoint. */
                    var lofsargs = [];

                    dprintf('lofs-mounted bootpool path "%s" on "%s".\n',
                        bootfs, mountpoint);

                    lofsargs.push('-F');
                    lofsargs.push('lofs');
                    lofsargs.push(bootfs);
                    lofsargs.push(mountpoint);
                    mod_child.execFile('mount', lofsargs, function (err,
                        stdout, stderr) {
                        if (err) {
                            callback(new VError(err, 'Cannot lofs mount %s',
                                bootfs));
                        } else {
                            callback(null, mountpoint);
                        }
                        return;
                    });
                }

                lib_usbkey.get_mount_info(mountpoint, function (err, mi) {
                    if (err) {
                        callback(
                            new VError(err,
                                'could not inspect mounted filesystems'), '');
                        return;
                    }

                    if (mi !== false) {
                        mod_assert.strictEqual(mi.mi_mountpoint, mountpoint);

                        dprintf('unmounting "%s"\n', mi.mi_mountpoint);
                        lib_oscmds.umount({
                            mt_mountpoint: mountpoint
                        }, function (err) {
                            if (err) {
                                callback(
                                    new VError(err,
                                        'count not unmount filesystem'), '');
                                return;
                            } else {
                                dprintf('unmounted\n');
                            }
                            do_lofs_mount(bootfs, mountpoint, callback);
                        });
                    } else {
                        dprintf('ok, nothing is mounted.\n');
                        do_lofs_mount(bootfs, mountpoint, callback);
                    }
                });
            });
        });
    });
}

function
get_variable(name, callback)
{
    var self = this;

    mod_assert.string(name, 'name');
    mod_assert.func(callback, 'callback');

    ensure_bootfs_mounted(self.bootpool, function (err, mountpoint) {
        if (err) {
            callback(err);
            return;
        }

        get_bootfs_mount_status(mountpoint, function (err, status) {
            if (err) {
                callback(err);
                return;
            }

            mod_assert.equal(status.version, 2);
            lib_usbkey.get_variable_loader(status.mountpoint, name, callback);
            return;
        });
    });
}

function
set_variable(name, value, callback)
{
    var self = this;

    mod_assert.string(name, 'name');
    mod_assert.string(name, 'value');
    mod_assert.func(callback, 'callback');

    ensure_bootfs_mounted(self.bootpool, function (err, mountpoint) {
        if (err) {
            callback(err);
            return;
        }

        get_bootfs_mount_status(mountpoint, function (err, status) {
            if (err) {
                callback(err);
                return;
            }

            mod_assert.equal(status.version, 2);
            lib_usbkey.set_variable_loader(status.mountpoint, name, value,
                callback);
            return;
        });
    });
}

module.exports = {
    get_bootfs_mount_status: get_bootfs_mount_status,
    get_variable: get_variable,
    ensure_bootfs_mounted: ensure_bootfs_mounted,
    set_variable: set_variable,
    triton_bootpool: triton_bootpool
};
