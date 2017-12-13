/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2017, Joyent, Inc.
 */


var mod_child = require('child_process');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var lib_common = require('../lib/common');

var VError = mod_verror.VError;
var dprintf = lib_common.dprintf;

var ZONENAME = '/usr/bin/zonename';
var UMOUNT = '/sbin/umount';
var MOUNT = '/sbin/mount';
var DISKINFO = '/usr/bin/diskinfo';
var FSTYP = '/usr/sbin/fstyp';
var SYNC = '/usr/bin/sync';

var FSTYP_IGNORE_MESSAGES = [
    'unknown_fstyp (cannot open device)',
    'unknown_fstyp (no matches)'
];

function
make_env()
{
    var env = {};
    var names = Object.keys(process.env);

    for (var i = 0; i < names.length; i++) {
        var name = names[i];

        if (name === 'LANG' || name.match(/^LC_/)) {
            /*
             * Do not copy any locale variables into the child environment.
             * See environ(5) for more information about what these variables
             * mean.
             */
            continue;
        }

        env[name] = process.env[name];
    }

    /*
     * Force the POSIX locale so that error messages are presented
     * consistently.
     */
    env.LANG = env.LC_ALL = 'C';

    return (env);
}

function
sync(callback)
{
    mod_assert.func(callback, 'callback');

    mod_child.execFile(SYNC, [], {
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'could not sync: %s', stderr.trim()));
            return;
        }

        callback(null);
    });
}

function
zonename(callback)
{
    mod_assert.func(callback, 'callback');

    mod_child.execFile(ZONENAME, [], {
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'could not get zonename: %s',
              stderr.trim()));
            return;
        }

        callback(null, stdout.trim());
    });
}

function
mount(options, callback)
{
    mod_assert.object(options, 'options');
    mod_assert.string(options.mt_fstype, 'mt_fstype');
    mod_assert.string(options.mt_mountpoint, 'mt_mountpoint');
    mod_assert.string(options.mt_special, 'mt_special');
    mod_assert.optionalObject(options.mt_options, 'mt_options');
    mod_assert.optionalNumber(options.mt_timeout, 'mt_timeout');
    mod_assert.func(callback, 'callback');

    /*
     * Assemble arguments to mount(1M):
     */
    var args = [];

    args.push('-F');
    args.push(options.mt_fstype);

    if (options.mt_options) {
        var o_args = [];
        for (var k in options.mt_options) {
            if (options.mt_options[k] === true) {
                o_args.push(k);
            } else if (options.mt_options[k] === false) {
                o_args.push('no' + k);
            } else {
                mod_assert.string(options.mt_options[k], 'mt_options[' + k +
                  ']');

                o_args.push(k + '=' + options.mt_options[k]);
            }
        }

        if (o_args.length > 0) {
            args.push('-o');
            args.push(o_args.join(','));
        }
    }

    args.push(options.mt_special);
    args.push(options.mt_mountpoint);

    dprintf('mount args: %s\n', args.join(' '));

    /*
     * Invoke mount(1M):
     */
    mod_child.execFile(MOUNT, args, {
        timeout: options.mt_timeout || 0,
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            var semsg = stderr.trim();
            var ve = new VError(err, 'mount of "%s" (fstyp %s) at "%s" ' +
              'failed: %s', options.mt_special, options.mt_fstype,
              options.mt_mountpoint, stderr.trim());

            /*
             * Put some properties on the error so that programmatic
             * consumers can reason about the error:
             */
            ve.mount_fstype = options.mt_fstype;
            ve.mount_mountpoint = options.mt_mountpoint;
            ve.mount_special = options.mt_special;
            ve.mount_stderr = semsg;

            switch (semsg) {
            case 'mount: Read-only file system':
                ve.mount_code = 'EROFS';
                break;
            default:
                ve.mount_code = 'UNKNOWN';
                break;
            }

            callback(ve);
            return;
        }

        callback();
    });
}

function
umount(options, callback)
{
    mod_assert.object(options, 'options');
    mod_assert.string(options.mt_mountpoint, 'mt_mountpoint');
    mod_assert.optionalNumber(options.mt_timeout, 'mt_timeout');
    mod_assert.func(callback, 'callback');

    /*
     * Invoke umount(1M):
     */
    mod_child.execFile(UMOUNT, [
        options.mt_mountpoint
    ], {
        timeout: options.mt_timeout || 0,
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            var busymsg = 'umount: ' + options.mt_mountpoint + ' busy';
            if (err.code === 1 && stderr.trim() === busymsg) {
                var e = new VError(err, 'umount "%s" failed, filesystem busy',
                  options.mt_mountpoint);
                e.code = 'EBUSY';
                callback(e);
                return;
            }

            callback(new VError(err, 'umount failed: %s', stderr.trim()));
            return;
        }

        callback();
    });
}

function
contains(list, str)
{
    mod_assert.arrayOfString(list, 'list');
    mod_assert.string(str, 'str');

    return (list.indexOf(str) !== -1);
}

function
fstyp(device, callback)
{
    mod_assert.string(device, 'device');
    mod_assert.func(callback, 'callback');

    mod_child.execFile(FSTYP, [ device ], {
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            /*
             * Did this process exit normally?
             */
            var exited = (typeof (err.code) === 'number');

            /*
             * The fstyp(1M) program emits a number of diagnostic messages.
             * Check to see if the output matches a message that effectively
             * translates to the absence of a detectable filesystem.
             */
            if (exited && contains(FSTYP_IGNORE_MESSAGES, stderr.trim())) {
                callback(null, false);
                return;
            }

            callback(new VError(err, 'could not determine fs on "%s"', device));
            return;
        }

        callback(null, stdout.trim());
    });
}

function
diskinfo(callback)
{
    mod_assert.func(callback, 'callback');

    mod_child.execFile(DISKINFO, ['-Hp' ], {
        env: make_env()
    }, function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'could not enumerate disk devices'));
            return;
        }

        var disks = [];
        var lines = stdout.split(/\n/);
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i]) {
                /*
                 * Skip blank lines.
                 */
                continue;
            }

            var fields = lines[i].split(/\t/);

            if (fields.length !== 7) {
                callback(new VError(err, 'invalid diskinfo line: %s',
                  lines[i]));
                return;
            }

            mod_assert.ok(fields[5] === 'yes' || fields[5] === 'no');
            mod_assert.ok(fields[6] === 'yes' || fields[6] === 'no');

            disks.push({
                dsk_type: fields[0],
                dsk_device: fields[1],
                dsk_vendor: fields[2],
                dsk_product: fields[3],
                dsk_size: Number(fields[4]),
                dsk_removeable: fields[5] === 'yes' ? true : false,
                dsk_ssd: fields[6] === 'yes' ? true : false
            });
        }

        callback(null, disks);
    });
}

module.exports = {
    sync: sync,
    zonename: zonename,
    mount: mount,
    umount: umount,
    fstyp: fstyp,
    diskinfo: diskinfo
};

/* vim: set ts=4 sts=4 sw=4 et: */
