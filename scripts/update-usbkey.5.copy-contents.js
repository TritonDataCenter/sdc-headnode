#!/usr/node/bin/node

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2019, Joyent, Inc.
 */


var mod_path = require('path');
var mod_fs = require('fs');
var mod_util = require('util');
var mod_crypto = require('crypto');

var mod_assert = require('assert-plus');
var mod_getopt = require('posix-getopt');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

/*
 * In order to cope with running this software on an unknown version of Node
 * (at least the 0.8 and 0.10 branches have been included in various platform
 * images), we import the external streams module:
 */
var mod_stream = require('readable-stream');

var lib_oscmds = require('/opt/smartdc/lib/oscmds.js');

var VError = mod_verror.VError;

function
wrap_stream(oldstream)
{
    var newstream = new mod_stream.Readable();

    return (newstream.wrap(oldstream));
}

function
shasum_file(path, callback)
{
    mod_assert.string(path, 'path');
    mod_assert.func(callback, 'callback');

    var sum = mod_crypto.createHash('sha1');

    /*
     * So that we may use the 'readable' event, and the read() method, we wrap
     * the file stream in the external streams module:
     */
    var fstr = wrap_stream(mod_fs.createReadStream(path));
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

    /*
     * So that we may get modern pipe() behaviour, we wrap the source stream in
     * the external streams module:
     */
    var fin = wrap_stream(mod_fs.createReadStream(src, {
        flags: 'r',
        encoding: null
    }));
    var fout = mod_fs.createWriteStream(tmpf, {
        flags: 'wx',
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

    fin.on('error', function (err) {
        cb(new VError(err, 'safe_copy src file "%s" error', src));
    });
    fout.on('error', function (err) {
        cb(new VError(err, 'safe_copy dst file "%s" error', tmpf));
    });

    /*
     * We should be using the 'finish' event here, but apparently that did
     * not exist in node version prior to 0.10 -- instead, we will use
     * the 'close' event.
     */
    fout.on('close', function () {
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
do_copy(opts, callback)
{
    mod_assert.object(opts, 'opts');
    mod_assert.string(opts.src, 'src');
    mod_assert.string(opts.dst, 'dst');
    mod_assert.bool(opts.dryrun, 'dryrun');
    mod_assert.bool(opts.verbose, 'verbose');
    mod_assert.func(callback, 'callback');

    if (opts.dryrun)
        opts.verbose = true;

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

                if (opts.verbose) {
                    console.log('create file "%s"', relp);
                    console.log('\tnew shasum: %s', sum);
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

                if (opts.verbose) {
                    console.log('update file "%s"', relp);
                    console.log('\told shasum: %s', dstsum);
                    console.log('\tnew shasum: %s', sum);
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
            callback(null);
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

                if (opts.verbose) {
                    console.log('mkdir "%s"', dir);
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

if (require.main === module) {
    var parser = new mod_getopt.BasicParser('nv', process.argv);

    var dryrun = false;
    var verbose = false;
    var option;

    while ((option = parser.getopt()) !== undefined) {
        switch (option.option) {
            case 'n':
               dryrun = true;
               break;

           case 'v':
               verbose = true;
               break;

           default:
               mod_assert.equal('?', option.option);
               process.exit(2);
               break;
        }
    }

    if (parser.optind() + 2 != process.argv.length) {
        console.log('missing arguments');
        process.exit(2);
    }

    var contents = process.argv[parser.optind()];
    var mountpoint = process.argv[parser.optind() + 1];

    do_copy({
        src: contents,
        dst: mountpoint,
        verbose: verbose,
        dryrun: dryrun
    }, function (err) {
        if (err) {
            console.log(err.message);
            process.exit(1);
            return;
        }

        /*
         * Give pcfs(7FS) and the USB key a few seconds to
         * settle while we knock on wood after the sync.
         */
        if (!dryrun) {
            lib_oscmds.sync(function () {
                setTimeout(function () {
                   process.exit(0);
                }, 5000);
            });
            return;
        }

        process.exit(0);
    });
}

/* vim: set ts=4 sts=4 sw=4 et: */
