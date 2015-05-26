/* vim: set ts=4 sts=4 sw=4 et: */

var mod_path = require('path');
var mod_fs = require('fs');
var mod_util = require('util');
var mod_crypto = require('crypto');

var mod_assert = require('assert-plus');
var mod_cmdln = require('cmdln');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_oscmds = require('../lib/oscmds');
var lib_usbkey = require('../lib/usbkey');

var VError = mod_verror.VError;

var UPDATE_FILE_SOURCE = '/opt/smartdc/share/usbkey';

function
Usbkey()
{
    var self = this;

    self.uk_ngz = false;

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

    if (opts.verbose) {
        /*
         * XXX
         */
        process.env.DEBUG = 'yes';
    }

    lib_oscmds.zonename(function (err, zonename) {
        if (!err && zonename !== 'global') {
            self.uk_ngz = true;
        }

        mod_cmdln.Cmdln.prototype.init.call(self, opts, args, callback);
    });
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

    lib_usbkey.ensure_usbkey_mounted({
        timeout: 45 * 1000
    }, function (err, mtpt) {
        if (err) {
            callback(err);
            return;
        }

        console.error('mounted');
        console.log('%s', mtpt);
        callback();
    });
};
Usbkey.prototype.do_mount.options = [
    {
        names: [ 'help', 'h', '?' ],
        type: 'bool',
        help: 'Print this help message.'
    }
];
Usbkey.prototype.do_mount.help = [
    'Mount the USB key if it is not mounted.',
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
        timeout: 45 * 1000
    }, function (err) {
        if (err) {
            callback(err);
            return;
        }

        console.error('unmounted');
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

    lib_usbkey.get_usbkey_mount_status(function (err, status) {
        if (err) {
            callback(err);
            return;
        }

        if (opts.json) {
            console.log(JSON.stringify(status));
        } else {
            if (opts.more) {
                console.log(status.message);
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
    'Get the current mount status of the USB key.',
    '',
    'Usage:',
    '     sdc-usbkey status [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

function
shasum_file(path, callback)
{
    mod_assert.string(path, 'path');
    mod_assert.func(callback, 'callback');

    var sum = mod_crypto.createHash('sha1');

    var fstr = mod_fs.createReadStream(path);
    fstr.on('error', function (err) {
        callback(new VError(err, 'could not shasum file "%s"', path));
        return;
    });
    fstr.on('readable', function () {
        for (;;) {
            var d = fstr.read();
            if (!d)
                return;
            sum.update(d);
        }
    });
    fstr.on('end', function () {
        callback(null, sum.digest('hex'));
    });
}

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
safe_copy(src, dst, callback)
{
    mod_assert.string(src, 'src');
    mod_assert.string(dst, 'dst');
    mod_assert.func(callback, 'callback');

    var tmpn = '.tmp.' + process.pid + '.' + mod_path.basename(dst);
    var tmpf = mod_path.join(mod_path.dirname(dst), tmpn);

    var fout = mod_fs.createWriteStream(tmpf, {
        flags: 'wx',
        encoding: null
    });
    var fin = mod_fs.createReadStream(src, {
        flags: 'r',
        encoding: null
    });
    var cb_fired = false;
    var cb = function (err) {
        fout.removeAllListeners();
        fin.removeAllListeners();

        mod_assert.ok(!cb_fired, 'cb fired twice');
        cb_fired = true;
        callback(err);
    };

    fout.on('error', function (err) {
        cb(new VError(err, 'safe_copy dst file "%s" error', tmpf));
    });
    fin.on('error', function (err) {
        cb(new VError(err, 'safe_copy src file "%s" error', src));
    });

    fout.on('finish', function () {
        mod_fs.rename(tmpf, dst, function (err) {
            if (err) {
                cb(new VError(err, 'could not rename tmp file "%s" to ' +
                  'dst "%s"', tmpf, dst));
                return;
            }

            cb();
        });
    });

    fin.pipe(fout);
}

function
run_update(opts, callback)
{
    mod_assert.object(opts, 'opts');
    mod_assert.string(opts.src, 'src');
    mod_assert.string(opts.dst, 'dst');
    mod_assert.bool(opts.dryrun, 'dryrun');
    mod_assert.bool(opts.progress, 'progress');
    mod_assert.func(callback, 'callback');

    var top = mod_path.resolve(opts.src);
    var topd = mod_path.resolve(opts.dst);

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

    if (!dir_check(top) || !dir_check(topd)) {
        return;
    }

    var actions = [];
    var dirs = [ '' ];

    var process_file = function (relp, next) {
        var srcf = mod_path.join(top, relp);
        var dstf = mod_path.join(topd, relp);

        shasum_file(srcf, function (err, sum) {
            if (err) {
                next(err);
                return;
            }

            var std = lstat(dstf);
            if (!std) {
                /*
                 * The file does not exist.  Copy the source file.
                 */
                actions.push({
                    a_type: 'CREATE_FILE',
                    a_relpath: relp,
                    a_src: {
                        path: srcf,
                        shasum: sum
                    },
                    a_dst: {
                        path: dstf
                    }
                });

                if (opts.progress) {
                    console.error('create file "%s"', relp);
                    console.error('\tnew shasum: %s', sum);
                }

                if (opts.dryrun) {
                    next();
                    return;
                }

                safe_copy(srcf, dstf, next);
                return;
            }

            if (std.type !== 'file') {
                next(new VError('path "%s" exists, but is of type "%s", not' +
                  ' file', dstf, std.type));
                return;
            }

            shasum_file(dstf, function (_err, dstsum) {
                if (_err) {
                    next(_err);
                    return;
                }

                if (sum === dstsum) {
                    /*
                     * The destination and source file match.  No action is
                     * required.
                     */
                    next();
                    return;
                }

                actions.push({
                    a_type: 'UPDATE_FILE',
                    a_relpath: relp,
                    a_src: {
                        path: srcf,
                        shasum: sum
                    },
                    a_dst: {
                        path: dstf,
                        shasum: dstsum
                    }
                });

                if (opts.progress) {
                    console.error('update file "%s"', relp);
                    console.error('\told shasum: %s', dstsum);
                    console.error('\tnew shasum: %s', sum);
                }

                if (opts.dryrun) {
                    next();
                    return;
                }

                safe_copy(srcf, dstf, next);
            });

        });
    };

    var walk_dirs = function () {
        if (dirs.length === 0) {
            callback(null, actions);
            return;
        }

        var dir = dirs.shift();

        /*
         * If dir is the empty string, we are enumerating the top-level
         * directory; i.e. the USB key mountpoint itself.  Otherwise, this is a
         * subdirectory that may need to be created.
         */
        if (dir) {
            var dstdir = mod_path.resolve(mod_path.join(topd, dir));
            var ddst = lstat(dstdir);

            if (!ddst) {
                /*
                 * The target directory does not exist.  We must create it.
                 */
                actions.push({
                    a_type: 'CREATE_DIRECTORY',
                    a_relpath: dir,
                    a_dst: {
                        path: dstdir
                    }
                });

                if (opts.progress) {
                    console.error('mkdir "%s"', dir);
                }

                if (!opts.dryrun) {
                    try {
                        mod_fs.mkdirSync(dstdir, parseInt('0755', 8));
                    } catch (ex) {
                        callback(new VError(ex, 'failed to mkdir "%s"',
                          dstdir));
                        return;
                    }
                }
            }
        }

        /*
         * Walk each entry in the current source directory:
         */
        var ents = mod_fs.readdirSync(mod_path.join(top, dir));
        var files = [];
        for (var i = 0; i < ents.length; i++) {
            var ent = ents[i];
            var relp = mod_path.join(dir, ent);
            var srcp = mod_path.join(top, relp);
            var st = lstat(srcp);

            switch (st.type) {
            case 'dir':
                dirs.push(relp);
                break;

            case 'file':
                files.push(relp);
                break;

            default:
                callback(new VError('source file "%s" is of unsupported type' +
                  ' "%s"', srcp, st.type));
                return;
            }
        }

        mod_vasync.forEachPipeline({
            inputs: files,
            func: process_file
        }, function (err) {
            if (err) {
                callback(err);
                return;
            }

            setImmediate(walk_dirs);
        });
    };

    walk_dirs();
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

    if (!opts.hasOwnProperty('dryrun')) {
        opts.dryrun = false;
    }
    if (!opts.hasOwnProperty('json')) {
        opts.json = false;
    }

    mod_assert.bool(opts.dryrun, 'opts.dryrun');
    mod_assert.bool(opts.json, 'opts.json');

    var already_mounted = false;
    var actions;
    var mountpoint;

    mod_vasync.pipeline({
        funcs: [
            function (_, next) {
                /*
                 * Check if the USB key is already mounted.
                 */
                lib_usbkey.get_usbkey_mount_status(function (err, status) {
                    if (err) {
                        next(err);
                        return;
                    }

                    mod_assert.bool(status.ok, 'status.ok');
                    already_mounted = status.ok;
                    mountpoint = status.mountpoint;
                    next();
                });
            },
            function (_, next) {
                /*
                 * If the USB key is already mounted, we do not need to mount
                 * it now.
                 */
                if (already_mounted) {
                    next();
                    return;
                }

                lib_usbkey.ensure_usbkey_mounted({
                    timeout: 45 * 1000
                }, function (err, mtpt) {
                    if (err) {
                        next(err);
                        return;
                    }

                    mod_assert.string(mtpt, 'mtpt');
                    mountpoint = mtpt;
                    next();
                });
            },
            function (_, next) {
                mod_assert.string(mountpoint, 'mountpoint');

                /*
                 * The Compute Node Tools tarball (cn_tools.tar.gz) deploys a
                 * set of incremental updates to the USB key image.  Update
                 * the USB key from this directory.
                 */
                run_update({
                    src: UPDATE_FILE_SOURCE,
                    dst: mountpoint,
                    progress: !opts.json,
                    dryrun: opts.dryrun
                }, function (err, _acts) {
                    if (err) {
                        next(err);
                        return;
                    }

                    actions = _acts;

                    if (opts.dryrun || actions.length < 1) {
                        next();
                        return;
                    }

                    /*
                     * Invoke sync(1M) for good measure.
                     */
                    lib_oscmds.sync(function () {
                        /*
                         * Give pcfs(7FS) and the USB key a few seconds to
                         * settle while we knock on wood.
                         */
                        setTimeout(next, 5000);
                    });
                });
            },
            function (_, next) {
                /*
                 * If the USB key was not already mounted, then unmount it now.
                 */
                if (already_mounted) {
                    next();
                    return;
                }

                lib_usbkey.ensure_usbkey_unmounted({
                    timeout: 45 * 1000
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

        if (opts.json) {
            console.log(JSON.stringify(actions));
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
        names: [ 'json', 'j' ],
        type: 'bool',
        help: 'Emit status to stdout as a JSON object.'
    },
    {
        names: [ 'dryrun', 'n' ],
        type: 'bool',
        help: 'Do not copy files, just determine what action is required' +
          ' to update the USB key.'
    }
];
Usbkey.prototype.do_update.help = [
    'Update the files stored on the USB key.',
    '',
    'Usage:',
    '     sdc-usbkey update [OPTIONS]',
    '',
    '{{options}}'
].join('\n');

if (require.main === module) {
    mod_cmdln.main(Usbkey);
}
