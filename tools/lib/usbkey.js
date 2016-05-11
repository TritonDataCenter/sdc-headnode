/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2016 Joyent, Inc.
 */


var mod_fs = require('fs');
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
var SVCPROP = '/bin/svcprop';

var MOUNT_OPTIONS = {
    foldcase: true,
    noatime: true,
    hidden: true,
    clamptime: true,
    rw: true
};
mod_assert.ok(valid_usbkey_mount_options(MOUNT_OPTIONS));

/*
 * The expected mountpoint for the USB key FAT filesystem is configured as a
 * property on the "filesystem/smartdc" SMF service.  Look that property
 * up now.
 */
function
get_mountpoint(callback)
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

        var val = stdout.trim();
        if (!val) {
            callback(null, DEFAULT_MOUNTPOINT);
        } else {
            callback(null, mod_path.join('/mnt', val));
        }
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
valid_usbkey_mount_options(options)
{
    mod_assert.object(options, 'options');

    if (!options.hidden || options.nohidden) {
        /*
         * Allow access to files with the "system" or "hidden" bits
         * set.
         */
        return (false);
    }

    if (!options.foldcase || options.nofoldcase) {
        /*
         * To ensure a consistent view of files on the key, we must _always_
         * mount with "foldcase" enabled.
         */
        return (false);
    }

    if (!options.clamptime || options.noclamptime) {
        /*
         * Constrain filesystem timestamps such that they will fit within a
         * 32-bit time_t.
         */
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
 * as documnted in the manual page mnttab(4).  Attempt to locate an entry in
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

function
locate_pcfs_devices(callback)
{
    mod_assert.func(callback, 'callback');

    lib_oscmds.diskinfo(function (err, disks) {
        if (err) {
            callback(err);
            return;
        }

        var pcfs_devices = [];

        /*
         * Run 'fstyp' against the first partition (p1) of each device, looking
         * for the USB key FAT filesystem:
         */
        mod_vasync.forEachParallel({
            inputs: disks,
            func: function (dsk, next) {
                var path = '/dev/dsk/' + dsk.dsk_device + 'p1';

                lib_oscmds.fstyp(path, function (_err, type) {
                    if (_err) {
                        next(_err);
                        return;
                    }

                    if (type === 'pcfs' && pcfs_devices.indexOf(path) === -1) {
                        pcfs_devices.push(path);
                    }

                    next();
                });
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

    get_mountpoint(function (err, _mtpt) {
        if (err) {
            callback(new VError(err, 'could not read mount configuration'));
            return;
        }

        mtpt = _mtpt;
        dprintf('configured usbkey mountpoint: "%s"\n', mtpt);

        setImmediate(keep_trying);
    });
}

function
usbkey_mount_status_common(mountpoint, callback)
{
    mod_assert.string(mountpoint, 'mountpoint');
    mod_assert.func(callback, 'callback');

    var status = {
        mountpoint: mountpoint,
        device: null,
        options: null,
        steps: {
            mounted: false,
            options_ok: false,
            marker_file: false
        },
        ok: false,
        message: ''
    };

    dprintf('fetching mount information for "%s"\n', mountpoint);
    get_mount_info(mountpoint, function (err, mi) {
        if (err) {
            callback(new VError(err, 'could not inspect mounted ' +
              'filesystems'));
            return;
        }

        if (mi === false) {
            dprintf('"%s" is not mounted.\n', mountpoint);
            status.message = 'not mounted';
            callback(null, status);
            return;
        }

        /*
         * The filesystem is mounted.
         */
        status.steps.mounted = true;

        mod_assert.strictEqual(mi.mi_mountpoint, mountpoint);
        if (mi.mi_fstype !== 'pcfs' ||
          !valid_usbkey_mount_options(mi.mi_options)) {
            /*
             * The mount does not match both the expected filesystem
             * type and the expected mount options.
             */
            dprintf('"%s" is mounted, but with incorrect options: %j\n',
                mi.mi_mountpoint, mi.mi_options);
            status.message = 'mounted, but with incorrect options';
            callback(null, status);
            return;
        }

        /*
         * The filesystem mount options are correct.
         */
        status.steps.options_ok = true;
        status.device = mi.mi_special;
        status.options = mi.mi_options;

        dprintf('checking marker file...\n');
        check_for_marker_file(mi.mi_mountpoint, function (_err, exists) {
            if (_err) {
                callback(new VError(_err, 'failed to locate marker file'));
                return;
            }

            if (exists) {
                /*
                 * The marker file exists on the mounted filesystem.
                 */
                status.steps.marker_file = true;
                status.message = 'mounted';
                status.ok = true;
            } else {
                status.message = 'mounted, but marker file not found';
            }

            callback(null, status);
        });
    });
}

function
get_usbkey_mount_status(callback)
{
    mod_assert.func(callback, 'callback');

    dprintf('determining usb key mount status...\n');

    get_mountpoint(function (err, mtpt) {
        if (err) {
            callback(new VError(err, 'could not read mount configuration'));
            return;
        }

        dprintf('configured usbkey mountpoint: "%s"\n', mtpt);

        usbkey_mount_status_common(mtpt, function (err, status) {
            if (err) {
                callback(new VError(err, 'could not get mount status'));
                return;
            }

            callback(null, status);
        });
    });
}

function
ensure_usbkey_mounted(options, callback)
{
    mod_assert.object(options, 'options');
    mod_assert.optionalNumber(options.timeout, 'options.timeout');
    mod_assert.optionalBool(options.ignore_missing, 'options.ignore_missing');
    mod_assert.func(callback, 'callback');

    mod_assert.ok(valid_usbkey_mount_options(MOUNT_OPTIONS));

    dprintf('ensuring usb key is mounted...\n');

    var epoch = process.hrtime();
    var mtpt;
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

        dprintf('fetching mount status for "%s"\n', mtpt);
        usbkey_mount_status_common(mtpt, function (err, status) {
            if (err) {
                callback(new VError(err, 'could not inspect mounted ' +
                  'filesystems'));
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
                    mt_options: MOUNT_OPTIONS
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

            if (!status.steps.options_ok) {
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

    get_mountpoint(function (err, _mtpt) {
        if (err) {
            callback(new VError(err, 'could not read mount configuration'));
            return;
        }

        mtpt = _mtpt;
        dprintf('configured usbkey mountpoint: "%s"\n', mtpt);

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

module.exports = {
    ensure_usbkey_unmounted: ensure_usbkey_unmounted,
    ensure_usbkey_mounted: ensure_usbkey_mounted,
    get_usbkey_mount_status: get_usbkey_mount_status
};

/* vim: set ts=4 sts=4 sw=4 et: */
