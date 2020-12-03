/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2020 Joyent, Inc.
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
        mountpoint: null,
        device: null,
        version: null,
        options: null,
        steps: {
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
            status.ok = true;
            status.version = 2; /* Actually consumed by Triton components! */
            status.message = 'mounted';
        } else {
            status.message = 'Something not lofs-mounted on ' + mountpoint;
        }

        callback(null, status);
    });
}

/*
 * Mount bootfs onto the default mountpoint.
 */
function
ensure_bootfs_mounted(poolname, callback)
{
    var args = [];
    /* XXX KEBE ASKS -- use SMF properties? */
    var mountpoint = lib_usbkey.DEFAULT_MOUNTPOINT;

    mod_assert.func(callback, 'callback');
    mod_assert.string(poolname, 'poolname');

    dprintf('ensuring usb key is mounted (no altmountopts for bootfs)...\n');

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

        /* Make sure the mountpoint is there. */
        lib_usbkey.ensure_mountpoint_exists(mountpoint, function (err) {
            if (err) {
                callback(err, '');
                return;
            }
        });

        var bootfs = '/' + stdout.trim();
        /* XXX KEBE ASKS, check for /pool/boot standard? */

        /* See if anything is mounted in mountpoint already, and umount it. */
        dprintf('fetching pool mount ensure information for "%s"\n',
            mountpoint);
        lib_usbkey.get_mount_info(mountpoint, function mnttab_info(err, mi) {
            if (err) {
                callback(
                    new VError(err, 'could not inspect mounted filesystems'),
                        '');
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
                            new VError(err, 'count not unmount filesystem'),
                            '');
                        return;
                    } else {
                        dprintf('unmounted\n');
                    }
                });
            } else {
                dprintf('ok, nothing is mounted.\n');
            }
        });

        /* Okay, let's lofs-mount bootfs on to mountpoint. */
        var lofsargs = [];

        lofsargs.push('-F');
        lofsargs.push('lofs');
        lofsargs.push(bootfs);
        lofsargs.push(mountpoint);
        mod_child.execFile('mount', lofsargs, function (err, stdout, stderr) {
            if (err) {
                callback(new VError(err, 'Cannot lofs mount %s', bootfs));
            } else {
                callback(null, mountpoint);
            }
            return;
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

        /* XXX KEBE SAYS Feed default mountpoint for now. */
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

        /* XXX KEBE SAYS Feed default mountpoint for now. */
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
