/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2020 Joyent, Inc.
 */

var mod_fs = require('fs');
var mod_os = require('os');
var mod_path = require('path');
var mod_child = require('child_process');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');
var mod_vasync = require('vasync');

var lib_oscmds = require('../lib/oscmds');
var lib_common = require('../lib/common');

var VError = mod_verror.VError;
var dprintf = lib_common.dprintf;

var DEFAULT_MOUNTPOINT = '/mnt/usbkey';
var ALT_OPTS_SUFFIX = 'altmountopts';
var SVCPROP = '/bin/svcprop';

var DEFAULT_MOUNT_OPTIONS = {
    /*
     * To ensure a consistent view of files on the key, we must
     * mount with "foldcase" enabled.
     */
    foldcase: true,
    atime: false,
    /*
     * Allow access to files with the "system" or "hidden" bits
     * set.
     */
    hidden: true,
    /*
     * Constrain filesystem timestamps such that they will fit within a
     * 32-bit time_t.
     */
    clamptime: true,
    rw: true
};


function
obj_copy(obj, target) {
    if (!target) {
        target = {};
    }

    Object.keys(obj).forEach(function (k) {
        target[k] = obj[k];
    });

    return (target);
}

/*
 * The expected mountpoint for the USB key FAT filesystem is configured as a
 * property on the "filesystem/smartdc" SMF service.  Look that property
 * up now.
 *
 * This returns *two* mountpoints. The first is the default mountpoint used
 * for mounting with the default options. The second is a separate path
 * for mounting with alternative mount options.
 */
function
get_mountpoints(callback)
{
    mod_assert.func(callback, 'callback');

    var fmri = 'svc:/system/filesystem/smartdc:default';
    var prop = 'joyentfs/usb_mountpoint';

    mod_child.execFile(SVCPROP, [
        '-p', prop,
        fmri
    ], function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'svcprop failed: %s', stderr.trim()));
            return;
        }

        var base;
        var val = stdout.trim();
        if (val) {
            base = mod_path.join('/mnt', val);
        } else {
            base = DEFAULT_MOUNTPOINT;
        }

        callback(null, [base, base + '-' + ALT_OPTS_SUFFIX]);
    });
}

function
ensure_mountpoint_exists(mtpt, callback)
{
    mod_fs.lstat(mtpt, function (err, st) {
        if (err) {
            if (err.code === 'ENOENT') {
                dprintf('directory "%s" does not exist; creating.\n', mtpt);
                mod_fs.mkdir(mtpt, function (_err) {
                    if (!_err) {
                        callback();
                        return;
                    }

                    callback(new VError(_err, 'could not create mountpoint ' +
                      'directory "%s"', mtpt));
                });
                return;
            }

            callback(new VError(err, 'could not stat mountpoint "%s"', mtpt));
            return;
        }

        if (st.isDirectory()) {
            callback();
            return;
        }

        callback(new VError('mountpoint "%s" is not a directory', mtpt));
    });
}

function
equiv_usbkey_mount_options(a, b)
{
    mod_assert.object(a, 'a');
    mod_assert.object(b, 'b');

    var get_mount_option = function (obj, name) {
        var val = null;
        if (obj.hasOwnProperty(name)) {
            mod_assert.bool(obj[name], name);
            val = obj[name];
        } else if (obj.hasOwnProperty('no' + name)) {
            mod_assert.bool(obj['no' + name], 'no' + name);
            val = !obj['no' + name];
        }
        return (val);
    };

    /*
     * To test for equivalency, we require both `a` and `b` to define either
     * of the <name> or no<name> options. Otherwise, we'd have to know the
     * default value from mount_pcfs(1M), and that isn't straightforward
     * (varies by previous Solaris releases, not always documented, depends
     * on the media type).
     */
    var equiv_mount_option = function (name) {
        var a_val = get_mount_option(a, name);
        var b_val = get_mount_option(b, name);
        return (a_val === b_val);
    };

    if (! equiv_mount_option('hidden')) {
        dprintf('mount options differ: hidden');
        return (false);
    }
    if (! equiv_mount_option('foldcase')) {
        dprintf('mount options differ: foldcase');
        return (false);
    }
    if (! equiv_mount_option('clamptime')) {
        dprintf('mount options differ: clamptime');
        return (false);
    }

    return (true);
}

function
parse_mount_optstr(optstr)
{
    mod_assert.string(optstr, 'optstr');

    var out = {};
    var pairs = optstr.split(',');

    for (var i = 0; i < pairs.length; i++) {
        var pair = pairs[i];
        var eqidx = pair.indexOf('=');

        if (eqidx === -1) {
            /*
             * This is a name-only option; i.e. without a value.
             */
            out[pair.trim()] = true;
        } else {
            out[pair.substr(0, eqidx).trim()] = pair.substr(eqidx + 1).trim();
        }
    }

    return (out);
}

/*
 * The kernel makes the list of mounted filesystems available in /etc/mnttab,
 * as documented in the manual page mnttab(4).  Attempt to locate an entry in
 * this file for a given mount point.  If an entry is found, it will be
 * returned as an object; if not, Boolean(false) will be returned instead.
 */
function
get_mount_info(mount, callback)
{
    mod_assert.string(mount, 'mount');
    mod_assert.func(callback, 'callback');

    mod_fs.readFile('/etc/mnttab', {
        encoding: 'utf8'
    }, function (err, contents) {
        if (err) {
            callback(new VError(err, 'could not read /etc/mnttab'));
            return;
        }

        /*
         * This is necessary to deal with node 0.8.20.  For whatever reason,
         * specifying an encoding does not appear to result in a string
         * argument.
         */
        if (Buffer.isBuffer(contents)) {
            contents = contents.toString('utf8');
        }

        var mount_info = null;
        var lines = contents.split(/\n/);
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i]) {
                /*
                 * Skip blank lines.
                 */
                continue;
            }

            var fields = lines[i].split(/\t/);

            if (fields.length !== 5) {
                callback(new VError(err, 'invalid mnttab line: %s', lines[i]));
                return;
            }

            if (fields[1] === mount) {
                mount_info = {
                    mi_special: fields[0],
                    mi_mountpoint: fields[1],
                    mi_fstype: fields[2],
                    mi_options: parse_mount_optstr(fields[3]),
                    mi_time: new Date(Number(fields[4]) * 1000)
                };
                break;
            }
        }

        if (mount_info !== null) {
            callback(null, mount_info);
            return;
        } else {
            callback(null, false);
        }
    });
}

/*
 * A recognized key will have an MBR in one of two forms: either a legacy BIOS
 * image, with a grub-legacy version of 3.2 at 0x3e; or a loader(5)-produced MBR
 * with a major version of 2 at offset 0xfa.
 *
 * The former has the root pcfs at partition 1, the latter at (GPT) partition 2.
 * Both should have the standard MBR magic of 0xaa55.
 */
function
get_usb_key_version(device, callback)
{
    mod_assert.string(device, 'device');
    mod_assert.func(callback, 'callback');

    var COMPAT_VERSION_MAJOR = 3;
    var COMPAT_VERSION_MINOR = 2;
    var IMAGE_MAJOR = 2;

    var p0dev = device.replace(/[sp][0-9]+$/, 'p0');

    mod_fs.open(p0dev, 'r', function read_mbr(err, fd) {
        if (err) {
            callback(null, err);
            return;
        }

        var buffer = new Buffer(512);

        mod_fs.read(fd, buffer, 0, buffer.length, 0,
          function inspect_mbr(err, nr_read, buffer) {
            if (err) {
                mod_fs.close(fd, function () {
                    callback();
                });
                return;
            }

            if ((buffer[0x1fe] | buffer[0x1ff] << 8) !== 0xaa55) {
                mod_fs.close(fd, function () {
                    callback();
                });
                return;
            }

            var version = null;

            if (buffer[0x3e] === COMPAT_VERSION_MAJOR &&
                buffer[0x3f] === COMPAT_VERSION_MINOR) {
                version = 1;
            } else if (buffer[0xfa] === IMAGE_MAJOR) {
                version = 2;
            }

            mod_fs.close(fd, function () {
                if (version === null) {
                    callback(null,
                        new VError('unrecognised key version for ' + device));
                    return;
                }

                callback(version);
            });
        });
    });
}

/*
 * Figure out if the given disk is potentially the USB key we're looking for.
 * It should have a recognised version.
 *
 * As this is all we have to go on, we'll later make sure it really is a USB key
 * via check_for_marker_file().
 */
function
inspect_device(pcfs_devices, disk, callback)
{
    mod_assert.string(disk, 'disk');
    mod_assert.func(callback, 'callback');

    get_usb_key_version('/dev/dsk/' + disk + 'p0',
        function check_fstyp(version, err) {
        if (err) {
            callback();
            return;
        }

        var part = '/dev/dsk/' + disk;

        switch (version) {
        case 1:
            part += 'p1';
            break;
        case 2:
            part += 's2';
            break;
        default:
            callback();
            return;
        }

        lib_oscmds.fstyp(part, function (err, type) {
            if (err) {
                callback();
                return;
            }

            if (type === 'pcfs')
                pcfs_devices.push(part);

            callback();
        });
    });
}

function
locate_pcfs_devices(callback)
{
    mod_assert.func(callback, 'callback');

    lib_oscmds.diskinfo(function inspect_devices(err, disks) {
        if (err) {
            callback(err);
            return;
        }

        var pcfs_devices = [];

        mod_vasync.forEachParallel({
            inputs: disks,
            func: function (disk, next) {
                inspect_device(pcfs_devices, disk.dsk_device, next);
            }
        }, function (_err) {
            if (_err) {
                callback(_err);
                return;
            }

            callback(null, pcfs_devices);
        });
    });
}

/*
 * The SDC USB key image contains a marker file, ".joyliveusb", in the root
 * directory.  Look for this file under the mountpoint provided.
 */
function
check_for_marker_file(mountpoint, callback)
{
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.func(callback, 'callback');

    var path = mod_path.join(mountpoint, '.joyliveusb');
    mod_fs.lstat(path, function (err, st) {
        if (err) {
            if (err.code === 'ENOENT') {
                callback(null, false);
                return;
            }

            callback(new VError(err, 'failed stat on "%s"', path));
            return;
        }

        if (st.isFile()) {
            callback(null, true);
            return;
        }

        callback(null, false);
    });
}

function
timeout_has_passed(hrt_epoch, timeout)
{
    if (!timeout) {
        return (false);
    }

    var delta = process.hrtime(hrt_epoch);
    var ms = Math.floor(delta[0] * 1000 + delta[1] / 1000000);

    return (ms > timeout);
}

function
ensure_usbkey_unmounted(options, callback)
{
    mod_assert.object(options, 'options');
    mod_assert.optionalNumber(options.timeout, 'options.timeout');
    mod_assert.func(callback, 'callback');

    dprintf('ensuring usb key is not mounted...\n');

    var epoch = process.hrtime();
    var mtpt;

    var keep_trying = function () {
        if (timeout_has_passed(epoch, options.timeout)) {
            callback(new VError('unmount timeout expired'));
            return;
        }

        dprintf('fetching mount information for "%s"\n', mtpt);
        get_mount_info(mtpt, function (err, mi) {
            if (err) {
                callback(new VError(err, 'could not inspect mounted ' +
                  'filesystems'));
                return;
            }

            if (mi === false) {
                /*
                 * The filesystem is not mounted.
                 */
                dprintf('ok, usb key is not mounted.\n');
                callback();
                return;
            }

            mod_assert.strictEqual(mi.mi_mountpoint, mtpt);

            dprintf('unmounting usbkey at "%s"\n', mi.mi_mountpoint);
            lib_oscmds.umount({
                mt_mountpoint: mtpt
            }, function (_err) {
                if (_err && _err.code === 'EBUSY') {
                    dprintf('filesystem busy, retrying...\n');
                    setTimeout(keep_trying, 1000);
                    return;
                }

                if (_err) {
                    callback(new VError(_err, 'could not umount ' +
                      'filesystem'));
                    return;
                }

                setImmediate(keep_trying);
            });
        });
    };

    get_usbkey_mount_status(null, function (err, status) {
        if (err) {
            callback(err);
            return;
        }

        if (!status.steps.mounted) {
            dprintf('ok, usb key is not mounted.\n');
            callback();
        }

        mtpt = status.mountpoint;
        dprintf('usbkey mountpoint: "%s"\n', mtpt);
        setImmediate(keep_trying);
    });
}

/*
 * Update the given mount status object in-place for the given mountpoint
 * and, if `exp_mount_options` ("exp" == expected) is given, expected mount
 * options.
 *
 * This is used by `get_usbkey_mount_status()`.
 */
function
_get_mountpoint_status(status, mountpoint, exp_mount_options, callback) {
    mod_assert.object(status, 'status');
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.optionalObject(exp_mount_options, 'exp_mount_options');
    mod_assert.func(callback, 'callback');

    dprintf('fetching mount information for "%s"\n', mountpoint);
    get_mount_info(mountpoint, function on_mount_info(miErr, mi) {
        if (miErr) {
            callback(new VError(miErr,
                'could not inspect mounted filesystems'));
            return;
        }

        if (mi === false) {
            dprintf('"%s" is not mounted.\n', mountpoint);
            callback();
            return;
        }

        /*
         * The filesystem is mounted.
         */
        status.steps.mounted = true;
        status.mountpoint = mi.mi_mountpoint;
        status.device = mi.mi_special;
        status.options = mi.mi_options;

        get_usb_key_version(status.device, function (version, err) {
            if (err) {
                callback(err);
                return;
            }

            status.version = version;

            /*
             * If `exp_mount_options` is not given, then we skip checking
             * mount options and the marker file.
             */
            if (!exp_mount_options) {
                callback();
                return;
            }

            mod_assert.strictEqual(mi.mi_mountpoint, mountpoint);
            if (mi.mi_fstype !== 'pcfs' ||
                    !equiv_usbkey_mount_options(
                        mi.mi_options, exp_mount_options)) {
                /*
                 * The mount does not match both the expected filesystem
                 * type and the expected mount options.
                 */
                dprintf('"%s" is mounted, but with different options: %j\n',
                    mi.mi_mountpoint, mi.mi_options);
                callback();
                return;
            }

            /*
             * The filesystem mount options are as expected.
             */
            status.steps.options_ok = true;

            dprintf('checking marker file...\n');
            check_for_marker_file(mi.mi_mountpoint,
              function (markerErr, exists) {
                if (markerErr) {
                    callback(new VError(markerErr,
                        'failed to locate marker file'));
                    return;
                }

                if (exists) {
                    status.steps.marker_file = true;
                }

                callback();
            });
        });
    });

}

/**
 * Return a status object detailing the USB key mount status, compared to the
 * expected. "Expected" means as we'd expect for the given mount options.
 * The status object:
 *
 *  {
 *      "mountpoint": <The current mountpoint, if mounted, else `null`.>
 *      "device": <the USB device /dev/... path, if mounted>
 *      "version": <the integer version of the key format>
 *      "options": <the mount options object, if mounted>
 *      "steps": {
 *          "mounted": <A boolean indicating if the USB key is mounted at all.>
 *          "options_ok": <A boolean indicating if the current mount options
 *              match the expected.>
 *          "marker_file": <A boolean indicating if the mount includes the
 *              marker file (typically ".joyliveusb") that marks this as a
 *              Triton USB key. This is only checked if `options_ok = true`.>
 *      }
 *
 *      "ok": <A boolean indicating the USB key is mounted at the expected
 *          path and with the expected options.>
 *      "message": <A short string description of the mount status. This is
 *          used by `sdc-usbkey status -m`.>
 *  }
 *
 * If you just want to see if the USB key is mounted at all, you can call
 *      get_usbkey_mount_status(null, function (err, status) { ... });
 * and check `status.steps.mounted`.
 *
 * @param {Object} alt_mount_options - Optional. Alternative (i.e. non-default)
 *      mount options to expect, if any. Pass null/undefined to expect the
 *      the default mount options. This impacts the expected mountpoint,
 *      because non-default mount options always use the alternative mountpoint.
 * @param {Function} callback - `function (err, status)`
 */
function
get_usbkey_mount_status(alt_mount_options, callback)
{
    mod_assert.optionalObject(alt_mount_options, 'alt_mount_options');
    mod_assert.func(callback, 'callback');

    dprintf('determining usb key mount status...\n');

    var context = {
        status: {
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
            message: ''
        }
    };

    mod_vasync.pipeline({arg: context, funcs: [
        function get_expected_mount_details(ctx, next) {
            get_mountpoints(function (err, mtpts) {
                if (err) {
                    next(new VError(err, 'could not read mount configuration'));
                    return;
                }

                dprintf('configured usbkey mountpoints: "%s"\n',
                    mtpts.join('", "'));

                if (alt_mount_options &&
                    Object.keys(alt_mount_options).length > 0) {
                    /*
                     * Custom, i.e. non-default, options were given: use the
                     * alternative options mountpoint.
                     */
                    ctx.other_mountpoint = mtpts[0];
                    ctx.exp_mountpoint = mtpts[1];
                    ctx.exp_mount_options = obj_copy(DEFAULT_MOUNT_OPTIONS);
                    obj_copy(alt_mount_options, ctx.exp_mount_options);
                } else {
                    ctx.exp_mountpoint = mtpts[0];
                    ctx.other_mountpoint = mtpts[1];
                    ctx.exp_mount_options = obj_copy(DEFAULT_MOUNT_OPTIONS);
                }

                next();
            });
        },

        function handle_exp_mountpoint(ctx, next) {
            _get_mountpoint_status(ctx.status, ctx.exp_mountpoint,
                ctx.exp_mount_options, next);
        },

        function handle_other_mountpoint(ctx, next) {
            /*
             * If the USB is mounted at the expected mountpoint, then we
             * don't need to gather info for the other mountpoint.
             */
            if (ctx.status.steps.mounted) {
                next();
                return;
            }

            _get_mountpoint_status(ctx.status, ctx.other_mountpoint,
                null, next);
        },

        function set_ok_and_message(ctx, next) {
            if (!ctx.status.steps.mounted) {
                ctx.status.ok = false;
                ctx.status.message = 'not mounted';
            } else if (!ctx.status.steps.options_ok) {
                ctx.status.ok = false;
                ctx.status.message = 'mounted, but with different options';
            } else if (!ctx.status.steps.marker_file) {
                ctx.status.ok = false;
                ctx.status.message = 'mounted, but marker file not found';
            } else {
                ctx.status.ok = true;
                ctx.status.message = 'mounted';
            }
            next();
        }

    ]}, function (err) {
        callback(err, context.status);
    });
}

function
ensure_usbkey_mounted(options, callback)
{
    mod_assert.object(options, 'options');
    mod_assert.optionalNumber(options.timeout, 'options.timeout');
    mod_assert.optionalBool(options.ignore_missing, 'options.ignore_missing');
    mod_assert.optionalObject(options.alt_mount_options,
        'options.alt_mount_options');
    mod_assert.func(callback, 'callback');

    dprintf('ensuring usb key is mounted (altmountopts: %j)...\n',
        options.alt_mount_options);

    var epoch = process.hrtime();
    var mtpt;
    var mount_options;
    var specials = null;

    /*
     * Callback wrapper for all cases where we have run out of devices to
     * inspect without locating a USB key, but have not experienced any
     * other fatal errors:
     */
    var missing = function (msg) {
        mod_assert.string(msg, 'msg');

        if (options.ignore_missing) {
            /*
             * The caller has requested that the lack of a USB key
             * not be treated as an error condition.
             */
            dprintf('%s, but ignore_missing is set\n', msg);
            callback(null, false);
            return;
        }

        callback(new VError(msg));
    };

    /*
     * This worker function is called repeatedly until a valid USB key
     * is mounted, or there are no candidate devices left mount:
     */
    var keep_trying = function () {
        if (specials.length === 0) {
            /*
             * There are no devices left to try mounting.  Give up.
             */
            missing('no suitable devices found for usbkey mount');
            return;
        }

        if (timeout_has_passed(epoch, options.timeout)) {
            callback(new VError('mount timeout expired'));
            return;
        }

        get_usbkey_mount_status(options.alt_mount_options,
          function (statusErr, status) {
            if (statusErr) {
                callback(statusErr);
                return;
            }

            mod_assert.object(status, 'status');
            mod_assert.object(status.steps, 'status.steps');
            mod_assert.bool(status.steps.mounted, 'steps.mounted');
            mod_assert.bool(status.steps.options_ok, 'steps.options_ok');
            mod_assert.bool(status.steps.marker_file, 'steps.marker_file');

            if (!status.steps.mounted) {
                /*
                 * Filesystem not mounted.  Try to mount it from the first
                 * device in the list.
                 */
                dprintf('mounting "%s" @ "%s".\n', specials[0], mtpt);
                lib_oscmds.mount({
                    mt_fstype: 'pcfs',
                    mt_mountpoint: mtpt,
                    mt_special: specials[0],
                    mt_options: mount_options
                }, function (_err) {
                    if (!_err) {
                        /*
                         * The mount was successful.
                         */
                        setImmediate(keep_trying);
                        return;
                    }

                    if (_err.mount_code === 'EROFS') {
                        /*
                         * Some Dell machines have read-only virtual USB
                         * devices that are exposed through their iDRAC
                         * management facility.  These are never what we
                         * want, but their existence should not deter us
                         * from our search for the real USB key.
                         */
                        dprintf('skipping read-only device "%s"\n',
                          _err.mount_special);

                        var idx = specials.indexOf(_err.mount_special);
                        if (idx !== -1) {
                            /*
                             * Remove the read-only device from the candidate
                             * list:
                             */
                            specials.splice(idx, 1);
                        }

                        setImmediate(keep_trying);
                        return;
                    }

                    callback(new VError(_err, 'could not mount filesystem'));
                });
                return;
            }

            if (status.mountpoint !== mtpt || !status.steps.options_ok) {
                /*
                 * The mount does not match both the expected filesystem
                 * type and the expected mount options.  Unmount it, and
                 * try again.
                 */
                dprintf('unmounting "%s"\n', status.mountpoint);
                lib_oscmds.umount({
                    mt_mountpoint: status.mountpoint
                }, function (_err) {
                    if (_err) {
                        if (_err.code === 'EBUSY') {
                            dprintf('filesystem busy, retrying...\n');
                            setTimeout(keep_trying, 1000);
                            return;
                        }

                        callback(new VError(_err, 'could not unmount ' +
                          'filesystem'));
                        return;
                    }

                    setImmediate(keep_trying);
                });
                return;
            }

            if (!status.steps.marker_file) {
                /*
                 * The mount was successful, but the marker file was not found.
                 * Remove this filesystem from the candidate list, unmount it,
                 * and move on to the next one.
                 */
                mod_assert.string(status.device, 'status.device');
                dprintf('marking file not found; ignoring "%s"\n',
                  status.device);

                dprintf('unmounting "%s"\n', status.mountpoint);
                lib_oscmds.umount({
                    mt_mountpoint: status.mountpoint
                }, function (_err) {
                    if (_err) {
                        if (_err.code === 'EBUSY') {
                            dprintf('filesystem busy, retrying...\n');
                            setTimeout(keep_trying, 1000);
                            return;
                        }

                        callback(new VError(_err, 'could not unmount ' +
                          'filesystem'));
                        return;
                    }

                    var idx = specials.indexOf(status.device);
                    if (idx !== -1) {
                        /*
                         * Remove the device we unmounted from the candidate
                         * list:
                         */
                        specials.splice(idx, 1);
                    }

                    setImmediate(keep_trying);
                });
                return;
            }

            /*
             * Mount is successful, and all checks passed.
             */
            dprintf('filesystem is mounted at "%s"\n', status.mountpoint);
            callback(null, status.mountpoint);
        });
    };

    get_mountpoints(function (err, mtpts) {
        if (err) {
            callback(new VError(err, 'could not read mount configuration'));
            return;
        }

        if (options.alt_mount_options &&
            Object.keys(options.alt_mount_options).length > 0) {
            /*
             * Custom, i.e. non-default, options were given: use the
             * alternative options mountpoint.
             */
            mtpt = mtpts[1];
            mount_options = obj_copy(DEFAULT_MOUNT_OPTIONS);
            obj_copy(options.alt_mount_options, mount_options);
        } else {
            mtpt = mtpts[0];
            mount_options = obj_copy(DEFAULT_MOUNT_OPTIONS);
        }

        dprintf('target usbkey mountpoint: "%s"\n', mtpt);
        dprintf('target mount options: %s\n', JSON.stringify(mount_options));

        ensure_mountpoint_exists(mtpt, function (_err) {
            if (_err) {
                callback(_err);
                return;
            }

            locate_pcfs_devices(function (__err, pcfs_devices) {
                if (__err) {
                    callback(new VError(__err, 'could not scan for pcfs'));
                    return;
                }

                if (pcfs_devices.length === 0) {
                    missing('no pcfs devices found');
                    return;
                }

                specials = pcfs_devices;
                dprintf('candidate devices: %s\n', specials.join(', '));
                setImmediate(keep_trying);
            });
        });
    });
}

function
get_variable_loader(mountpoint, name, callback)
{
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.string(name, 'name');
    mod_assert.func(callback, 'callback');

    var search = '^\\s*' + name + '\\s*=\\s*"?\([^"]*\)"?\\s*$';
    var file = mountpoint + '/boot/loader.conf';
    var value = null;

    mod_fs.readFile(file, 'utf8', function (err, data) {
        if (err) {
            callback(new VError(err, 'failed to read ' + file));
            return;
        }

        var lines = data.replace(/\n$/, '').split(mod_os.EOL);

        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(search);
            if (m) {
                 value = m[1];
            }
        }

        /*
         * This file over-rides the previous one.
         */
        file = mountpoint + '/boot/loader.conf.local';

        mod_fs.readFile(file, 'utf8', function (err, data) {
            if (err) {
                if (err.code === 'ENOENT') {
                    callback(null, value);
                } else {
                    callback(new VError(err, 'failed to read ' + file));
                }
                return;
            }

            var lines = data.replace(/\n$/, '').split(mod_os.EOL);

            for (var i = 0; i < lines.length; i++) {
                var m = lines[i].match(search);
                if (m) {
                    value = m[1];
                }
            }

            callback(null, value);
        });
    });
}

function
get_variable(name, callback)
{
    mod_assert.string(name, 'name');
    mod_assert.func(callback, 'callback');

    ensure_usbkey_mounted({}, function (err) {
        if (err) {
            callback(err);
            return;
        }

        get_usbkey_mount_status({}, function (err, status) {
            if (err) {
                callback(err);
                return;
            }

            switch (status.version) {
            case 1:
                callback(new VError('get-variable is not supported for grub'));
                return;
            case 2:
                get_variable_loader(status.mountpoint, name, callback);
                return;
            default:
                callback(new VError('unknown USB key version ' +
                    status.version));
                return;
            }
        });
    });
}

function
sedfile(file, search, replace, callback)
{
    mod_assert.string(file, 'file');
    mod_assert.string(search, 'search');
    mod_assert.string(replace, 'replace');
    mod_assert.func(callback, 'callback');

    mod_fs.readFile(file, 'utf8', function (err, data) {
        var outfile = file + '.tmp';
        var replaced = false;
        var out = '';
        var i;

        if (err) {
            callback(new VError(err, 'failed to read ' + file));
            return;
        }

        var lines = data.replace(/\n$/, '').split(mod_os.EOL);

        for (i = 0; i < lines.length; i++) {
            var line = lines[i];
            out += line.replace(new RegExp(search, 'g'), function () {
                replaced = true;
                return replace;
            });
            out += mod_os.EOL;
        }

        if (!replaced) {
            out += replace + '\n';
        }

        mod_fs.writeFile(outfile, out, 'utf8', function (err) {
            if (err) {
                callback(new VError(err, 'failed to write ' + outfile));
                return;
            }

            mod_fs.rename(outfile, file, function (err) {
                if (err) {
                    callback(new VError(err, 'failed to rename ' + outfile));
                    return;
                }

                callback();
            });
        });
    });
}

function
set_variable_grub(mountpoint, name, value, callback)
{
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.string(name, 'name');
    mod_assert.string(value, 'value');
    mod_assert.func(callback, 'callback');

    /* Special handling: ipxe for grub means changing default */
    if (name === 'ipxe') {
        var search = '^\\s*default\\s+.*$';
        var replace;

        if (value === 'true') {
            replace = 'default 0';
        } else {
            replace = 'default 1';
        }
    } else if (name === 'os_console') {
        search = '^\\s*variable\\s+os_console\\s+.*$';
        replace = 'variable ' + name + ' ' + value;
    } else if (name === 'smt_enabled') {
        callback(new VError('setting kernel argument ' + name + ' ' + value +
            ' is not supported for grub; please edit menu.lst by hand'));
    } else {
        /*
         * Note that we're forced to assume here that this is a grub setting,
         * rather than a boot argument, as we cannot differentiate. This is
         * why we explicitly check for smt_enabled above.
         */
        search = '^\\s*' + name + '\\s+.*$';
        replace = name + ' ' + value;
    }

    sedfile(mountpoint + '/boot/grub/menu.lst',
        search, replace, function (err) {
        if (err) {
            callback(err);
            return;
        }

        sedfile(mountpoint + '/boot/grub/menu.lst.tmpl',
            search, replace, callback);
    });
}

function
set_variable_loader(mountpoint, name, value, callback)
{
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.string(name, 'name');
    mod_assert.string(value, 'value');
    mod_assert.func(callback, 'callback');

    var search = '^\\s*' + name + '\\s*=\\s*.*$';

    /*
     * Make sure the value is enclosed in quotes (") in case the value contains
     * embedded whitespace.  Otherwise, loader will fail to parse it correctly.
     */
    value = '"' + value + '"';

    var replace = name + '=' + value;

    sedfile(mountpoint + '/boot/loader.conf', search, replace, callback);
}

function
set_variable(name, value, callback)
{
    mod_assert.string(name, 'name');
    mod_assert.string(value, 'value');
    mod_assert.func(callback, 'callback');

    ensure_usbkey_mounted({}, function (err) {
        if (err) {
            callback(err);
            return;
        }

        get_usbkey_mount_status({}, function (err, status) {
            if (err) {
                callback(err);
                return;
            }

            switch (status.version) {
            case 1:
                set_variable_grub(status.mountpoint, name, value, callback);
                return;
            case 2:
                set_variable_loader(status.mountpoint, name, value, callback);
                return;
            default:
                callback(new VError('unknown USB key version ' +
                    status.version));
                return;
            }
        });
    });
}

module.exports = {
    DEFAULT_MOUNTPOINT: DEFAULT_MOUNTPOINT,
    check_for_marker_file: check_for_marker_file,
    ensure_mountpoint_exists: ensure_mountpoint_exists,
    ensure_usbkey_unmounted: ensure_usbkey_unmounted,
    ensure_usbkey_mounted: ensure_usbkey_mounted,
    get_mount_info: get_mount_info,
    get_usbkey_mount_status: get_usbkey_mount_status,
    get_variable: get_variable,
    get_variable_loader: get_variable_loader,
    set_variable: set_variable,
    set_variable_loader: set_variable_loader
};

/* vim: set ts=4 sts=4 sw=4 et: */
