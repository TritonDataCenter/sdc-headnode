/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2020 Joyent, Inc.
 */


var mod_fs = require('fs');
var mod_util = require('util');

var mod_assert = require('assert-plus');
var mod_cmdln = require('cmdln');
var mod_forkexec = require('forkexec');
var mod_glob = require('glob');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_oscmds = require('../lib/oscmds');
var lib_usbkey = require('../lib/usbkey');

var VError = mod_verror.VError;

var SECONDS = 1000;

var TIMEOUT_MOUNT = 120 * SECONDS;
var TIMEOUT_UNMOUNT = 45 * SECONDS;

var USBKEY_DIR = '/opt/smartdc/share/usbkey/';
var CONTENTS_DIR = USBKEY_DIR + 'contents/';

function
Usbkey()
{
    var self = this;

    self.uk_ngz = false;
    self.bootpool = '';

    mod_cmdln.Cmdln.call(self, {
        name: 'sdc-usbkey',
        desc: 'Utility for mounting, unmounting and updating the USB key',
        options: [
            {
                names: [ 'help', 'h', '?' ],
                type: 'bool',
                help: 'Print this help message.'
            },
            {
                names: [ 'usb', 'u' ],
                type: 'bool',
                help: 'Force USB key searching, if booted from a ZFS pool.'
            },
            {
                names: [ 'verbose', 'v' ],
                type: 'bool',
                help: 'Emit verbose status messages during operation.'
            }
        ]
    });
}
mod_util.inherits(Usbkey, mod_cmdln.Cmdln);

Usbkey.prototype.init = function
init(opts, args, callback)
{
    var self = this;

    self.verbose = opts.verbose;

    if (opts.verbose) {
        /*
         * We set DEBUG in our "environment" so that dprintf() can find it.
         * This could almost certainly be better.
         */
        process.env.DEBUG = 'yes';
    }

    lib_oscmds.zonename(function set_uk_ngz(err, zonename) {
        if (!err && zonename !== 'global') {
            self.uk_ngz = true;
        }
    });

    if (!opts.usb) {
        /*
         * Unless forced by -u/--usb, see if we booted from a ZFS pool
         * and set accordingly.
         */
        lib_oscmds.triton_pool(function set_booted_from_pool(err, pool) {
            if (!err && pool !== '') {
                self.bootpool = pool;
            }
        });
    }

    mod_cmdln.Cmdln.prototype.init.call(self, opts, args, callback);
};

Usbkey.prototype._global_zone_only = function
_global_zone_only(callback)
{
    var self = this;

    if (self.uk_ngz) {
        callback(new Error('this command must be used in the global zone'));
        return (false);
    }

    return (true);
};

/*
 * sdc-usbkey mount
 */
Usbkey.prototype.do_mount = function
do_mount(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    var alt_mount_options = {};
    if (opts.nofoldcase) {
        alt_mount_options.foldcase = false;
    }

    lib_usbkey.ensure_usbkey_mounted({
        timeout: TIMEOUT_MOUNT,
        alt_mount_options: alt_mount_options
    }, function (err, mtpt) {
        if (err) {
            callback(err);
            return;
        }

        console.log('%s', mtpt);
        callback();
    });
};
Usbkey.prototype.do_mount.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    },
    {
        name: 'nofoldcase',
        type: 'bool',
        help: 'Mount the USB key without folding case.'
    }
];
Usbkey.prototype.do_mount.help = [
    'Mount the USB key if it is not mounted.',
    '',
    'The USB key will be mounted at the configured mount point (by default',
    '"' + lib_usbkey.DEFAULT_MOUNTPOINT +
        '") when mounted with default options.',
    'If non-default options are requested, then an alternative mount point',
    'will be used. Note that `sdc-usbkey status` will report "unmounted" if',
    'the USB key is mounted with non-default options.',
    '',
    'Usage:',
    '     sdc-usbkey mount [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

/*
 * sdc-usbkey unmount
 */
Usbkey.prototype.do_unmount = function
do_unmount(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    lib_usbkey.ensure_usbkey_unmounted({
        timeout: TIMEOUT_UNMOUNT
    }, function (err) {
        if (err) {
            callback(err);
            return;
        }

        callback();
    });
};
Usbkey.prototype.do_unmount.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    }
];
Usbkey.prototype.do_unmount.help = [
    'Unmount the USB key if it is mounted.',
    '',
    'Usage:',
    '     sdc-usbkey unmount [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

/*
 * sdc-usbkey status
 */
Usbkey.prototype.do_status = function
do_status(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    lib_usbkey.get_usbkey_mount_status(null, function log_status(err, status) {
        if (err) {
            callback(err);
            return;
        }

        if (opts.json) {
            console.log(JSON.stringify(status));
        } else {
            if (opts.more) {
                if (status.steps.mounted) {
                    console.log('%s (%s)', status.message, status.mountpoint);
                } else {
                    console.log('%s', status.message);
                }
            } else {
                console.log(status.ok ? 'mounted' : 'unmounted');
            }
        }

        callback();
    });
};
Usbkey.prototype.do_status.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    },
    {
        names: [ 'json', 'j' ],
        type: 'bool',
        help: 'Emit status to stdout as a JSON object.'
    },
    {
        names: [ 'more', 'm' ],
        type: 'bool',
        help: 'Print more detail than just "mounted" or "unmounted".'
    }
];
Usbkey.prototype.do_status.help = [
    'Check if the USB key mounted with the default settings.',
    '',
    'Note that this will report "unmounted" if the USB key is mounted with',
    'non-default options. Use `sdc-usbkey status -m` for more details.',
    '',
    'Usage:',
    '     sdc-usbkey status [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

function
lstat(path)
{
    var st;

    try {
        st = mod_fs.lstatSync(path);
    } catch (ex) {
        if (ex.code === 'ENOENT') {
            return (null);
        }

        throw (ex);
    }

    mod_assert.object(st, 'st');

    if (st.isFile()) {
        st.type = 'file';
    } else if (st.isDirectory()) {
        st.type = 'dir';
    } else if (st.isBlockDevice()) {
        st.type = 'block';
    } else if (st.isCharacterDevice()) {
        st.type = 'char';
    } else if (st.isSymbolicLink()) {
        st.type = 'link';
    } else if (st.isFIFO()) {
        st.type = 'fifo';
    } else if (st.isSocket()) {
        st.type = 'socket';
    } else {
        st.type = 'unknown';
    }

    return (st);
}

function
run_update(opts, callback)
{
    mod_assert.object(opts, 'opts');
    mod_assert.string(opts.mountpoint, 'mountpoint');
    mod_assert.bool(opts.dryrun, 'dryrun');
    mod_assert.bool(opts.verbose, 'verbose');
    mod_assert.func(callback, 'callback');

    var dir_check = function (path) {
        var st = lstat(path);
        if (!st) {
            callback(new VError('directory "%s" does not exist', path));
            return (false);
        } else if (st.type !== 'dir') {
            callback(new VError('path "%s" should be a directory, but is "%s"',
              path, st.type));
            return (false);
        }
        return (true);
    };

    if (!dir_check(opts.mountpoint)) {
        return;
    }

    var args = [];
    if (opts.dryrun) {
        args.push('-n');
    }

    if (opts.verbose) {
        args.push('-v');
    }

    args.push(CONTENTS_DIR);
    args.push(opts.mountpoint);

    mod_vasync.forEachPipeline({
        func: function run_update_script(script, callback) {
            var argv = [ script ].concat(args);

            if (opts.verbose) {
                console.log('Executing ' + argv.join(' '));
            }

            mod_forkexec.forkExecWait({
                'argv': argv,
                'includeStderr': true
            }, function (err, info) {
                if (err) {
                   callback(err);
                   return;
                }

                console.log(info.stdout);
                callback();
            });
        },
        inputs: mod_glob.sync(USBKEY_DIR + '/update-usbkey.*')
    }, function (err) {
        if (err) {
            callback(err);
            return;
        }

        callback();
    });
}

/*
 * sdc-usbkey update
 */
Usbkey.prototype.do_update = function
do_update(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    opts.verbose = Boolean(self.verbose);

    if (!opts.hasOwnProperty('dryrun')) {
        opts.dryrun = false;
    }
    if (!opts.hasOwnProperty('ignore_missing')) {
        opts.ignore_missing = false;
    }

    mod_assert.bool(opts.dryrun, 'opts.dryrun');
    mod_assert.bool(opts.verbose, 'opts.verbose');
    mod_assert.bool(opts.ignore_missing, 'opts.ignore_missing');

    var cancel = false;
    var already_mounted = false;
    var mountpoint;

    mod_vasync.pipeline({
        funcs: [
            function get_usbkey_status(_, next) {
                if (cancel) {
                    next();
                    return;
                }

                /*
                 * Check if the USB key is already mounted with default opts.
                 */
                lib_usbkey.get_usbkey_mount_status(null,
                  function (err, status) {
                    if (err) {
                        next(err);
                        return;
                    }

                    mod_assert.bool(status.ok, 'status.ok');
                    already_mounted = status.ok;
                    if (already_mounted) {
                        mountpoint = status.mountpoint;
                    }
                    next();
                });
            },
            function mount_usbkey(_, next) {
                if (cancel) {
                    next();
                    return;
                }

                /*
                 * If the USB key is already mounted, we do not need to mount
                 * it now.
                 */
                if (already_mounted) {
                    next();
                    return;
                }

                lib_usbkey.ensure_usbkey_mounted({
                    timeout: TIMEOUT_MOUNT,
                    ignore_missing: opts.ignore_missing
                }, function (err, mtpt) {
                    if (err) {
                        next(err);
                        return;
                    }

                    if (opts.ignore_missing && mtpt === false) {
                        cancel = true;
                        next();
                        return;
                    }

                    mod_assert.string(mtpt, 'mtpt');
                    mountpoint = mtpt;
                    next();
                });
            },
            function do_run_update(_, next) {
                if (cancel) {
                    next();
                    return;
                }

                mod_assert.string(mountpoint, 'mountpoint');

                run_update({
                    mountpoint: mountpoint,
                    verbose: opts.verbose,
                    dryrun: opts.dryrun
                }, function (err) {
                    if (err) {
                        next(err);
                        return;
                    }

                    next();
                });
            },
            function unmount_usbkey(_, next) {
                if (cancel) {
                    next();
                    return;
                }

                /*
                 * If the USB key was not already mounted, then unmount it now.
                 */
                if (already_mounted) {
                    next();
                    return;
                }

                lib_usbkey.ensure_usbkey_unmounted({
                    timeout: TIMEOUT_UNMOUNT
                }, function (err) {
                    next(err);
                });
            }
        ],
        arg: {}
    }, function (err) {
        if (err) {
            callback(err);
            return;
        }

        if (cancel) {
            callback();
            return;
        }

        callback();
    });
};
Usbkey.prototype.do_update.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    },
    {
        names: [ 'dryrun', 'n' ],
        type: 'bool',
        help: 'Do not modify the key, just report changes.'
    },
    {
        names: [ 'ignore-missing', 'i' ],
        type: 'bool',
        help: 'In the event that the system does not have a USB key, report ' +
          ' success instead of an error.  All other errors are still fatal.'
    }
];
Usbkey.prototype.do_update.help = [
    'Update the USB key contents.',
    '',
    'Usage:',
    '     sdc-usbkey update [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

/*
 * sdc-usbkey get-variable
 */
Usbkey.prototype.do_get_variable = function
do_get_variable(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (args.length !== 1) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    lib_usbkey.get_variable(args[0], function (err, value) {
        if (!err) {
            if (value !== null) {
                console.log(value);
            } else {
                err = new VError('variable "%s" is not set', args[0]);
            }
        }

        callback(err);
    });
};
Usbkey.prototype.do_get_variable.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    }
];
Usbkey.prototype.do_get_variable.help = [
    'Get a bootloader variable',
    '',
    'Usage:',
    '     sdc-usbkey get-variable <name>',
    '',
    '{{options}}'
].join('\n');

/*
 * sdc-usbkey set-variable
 */
Usbkey.prototype.do_set_variable = function
do_set_variable(subcmd, opts, args, callback)
{
    var self = this;

    if (opts.help) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (args.length != 2) {
        self.do_help('help', {}, [ subcmd ], callback);
        return;
    }

    if (!self._global_zone_only(callback)) {
        return;
    }

    lib_usbkey.set_variable(args[0], args[1], function (err) {
        if (err) {
            callback(err);
            return;
        }

        callback();
    });
};
Usbkey.prototype.do_set_variable.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    }
];
Usbkey.prototype.do_set_variable.help = [
    'Set a grub/loader variable',
    '',
    'Usage:',
    '     sdc-usbkey set-variable <name> <value>',
    '',
    '{{options}}'
].join('\n');

if (require.main === module) {
    mod_cmdln.main(Usbkey);
}

/* vim: set ts=4 sts=4 sw=4 et: */
