/* vim: set ts=4 sts=4 sw=4 et: */

var mod_child = require('child_process');

var mod_assert = require('assert-plus');
var mod_extsprintf = require('extsprintf');
var mod_verror = require('verror');

var VError = mod_verror.VError;

var ZONENAME = '/usr/bin/zonename';
var UMOUNT = '/sbin/umount';
var MOUNT = '/sbin/mount';
var DISKINFO = '/usr/bin/diskinfo';
var FSTYP = '/usr/sbin/fstyp';
var SYNC = '/usr/bin/sync';

function
dprintf()
{
    if (!process.env.DEBUG) {
        return;
    }

    process.stderr.write(mod_extsprintf.sprintf.apply(null, arguments));
}

function
sync(callback)
{
    mod_assert.func(callback, 'callback');

    mod_child.execFile(SYNC, function (err, stdout, stderr) {
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

    mod_child.execFile(ZONENAME, function (err, stdout, stderr) {
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
        timeout: options.mt_timeout || 0
    }, function (err, stdout, stderr) {
        if (err) {
            callback(new VError(err, 'mount failed: %s', stderr.trim()));
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
        timeout: options.mt_timeout || 0
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
fstyp(device, callback)
{
    mod_assert.string(device, 'device');
    mod_assert.func(callback, 'callback');

    mod_child.execFile(FSTYP, [ device ], function (err, stdout, stderr) {
        if (err) {
            if (err.code === 7 && stderr.trim() ===
              'unknown_fstyp (cannot open device)') {
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

    mod_child.execFile(DISKINFO, [ '-Hp' ], function (err, stdout, stderr) {
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
