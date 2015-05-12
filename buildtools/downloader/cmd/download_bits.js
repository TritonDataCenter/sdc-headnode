#!/usr/bin/env node
/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_crypto = require('crypto');
var mod_fs = require('fs');
var mod_path = require('path');
var mod_util = require('util');

var mod_assert = require('assert-plus');
var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_jsprim = require('jsprim');
var mod_manta = require('manta');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_multi_progbar = require('../lib/multi_progbar');

var VError = mod_verror.VError;

/*
 * Globals:
 */
var EPOCH = process.hrtime();

var PROGBAR = new lib_multi_progbar.MultiProgressBar();

var CACHE_DIR;
var BITS_JSON = require('../../../bits.json');
var GLOBAL = {
	branch: 'master'
};

var BUILD_SPEC = load_json_file('../../../build.spec', true);
var BUILD_SPEC_LOCAL = load_json_file('../../../build.spec.local', false);

var DEBUG = process.env.DEBUG ? true : false;

function
generate_options()
{
	var options = [
		{
			names: [ 'cache', 'd' ],
			type: 'string',
			help: 'Cache directory'
		},
		{
			names: [ 'help', 'h' ],
			type: 'bool',
			help: 'Print this help and exit'
		}
	];

	return (options);
}

function
parse_opts(argv)
{
	var parser = mod_dashdash.createParser({
		options: generate_options(),
		allowUnknown: false
	});

	var usage = function (rc) {
		var p = (rc === 0) ? printf : errprintf;

		p('Usage: %s [OPTIONS]\noptions:\n%s\n',
		    mod_path.basename(__filename),
		    parser.help({
			    includeEnv: true
		    }));

		if (rc !== undefined) {
			process.exit(rc);
		}
	}

	var opts;
	try {
		opts = parser.parse(argv);
	} catch (ex) {
		errprintf('ERROR: %s', ex.stack);
		usage(1);
	}

	if (!opts.cache) {
		errprintf('ERROR: -d (--cache) is required\n');
		usage(1);
	}

	return (opts);
}

function
errprintf()
{
	process.stderr.write(mod_extsprintf.sprintf.apply(null, arguments));
}

function
printf()
{
	process.stdout.write(mod_extsprintf.sprintf.apply(null, arguments));
}

function
load_json_file(name, must_exist)
{
	var path;
	var fin;

	try {
		path = mod_path.resolve(mod_path.join(__dirname, name));
		fin = mod_fs.readFileSync(path, 'utf8');
		return (JSON.parse(fin));
	} catch (ex) {
		if (ex.code === 'ENOENT' && !must_exist) {
			return ({});
		}
		throw (new VError(ex, 'could not read JSON file "%s"',
		    path));
	}
}

function
build_spec(name)
{
	var ret1 = mod_jsprim.pluck(BUILD_SPEC_LOCAL, name);
	if (ret1 !== undefined && ret1 !== null) {
		return (ret1);
	}

	var ret0 = mod_jsprim.pluck(BUILD_SPEC, name);
	if (ret0 !== undefined && ret0 !== null) {
		return (ret0);
	}

	errprintf('build spec key "%s" not found', name);
	process.exit(1);
}

function
all_bits(input)
{
	var out = [];
	var keys;

	mod_assert.object(input.zones, 'zones');
	mod_assert.object(input.bits, 'bits');

	/*
	 * Load the list of zones from the configuration, generating a bit
	 * record for each of the manifest and the image of each zone.
	 */
	keys = Object.keys(input.zones || {});
	for (var i = 0; i < keys.length; i++) {
		var name = keys[i];
		var zone = input.zones[name];

		out.push({
			bit_name: name + '_manifest',
			bit_branch: zone.branch || GLOBAL.branch,
			bit_jobname: zone.jobname || name,
			bit_file: {
				base: (zone.jobname || name) + '-zfs',
				ext: 'imgmanifest'
			},
			bit_make_symlink: undefined
		});
		out.push({
			bit_name: name + '_image',
			bit_branch: zone.branch || GLOBAL.branch,
			bit_jobname: zone.jobname || name,
			bit_file: {
				base: (zone.jobname || name) + '-zfs',
				ext: 'zfs.gz'
			},
			bit_make_symlink: undefined
		});
	}

	/*
	 * Load any additional bits that are not part of a zone image:
	 */
	keys = Object.keys(input.bits || {});
	for (var i = 0; i < keys.length; i++) {
		var name = keys[i];
		var bit = input.bits[name];

		out.push({
			bit_name: name,
			bit_branch: bit.branch || GLOBAL.branch,
			bit_jobname: bit.jobname || name,
			bit_file: {
				base: bit.file.base,
				ext: bit.file.ext
			},
			bit_make_symlink: bit.symlink || undefined
		});
	}

	return (out);
}

var MANTA = mod_manta.createClient({
	user: build_spec('manta-user'),
	url: build_spec('manta-url'),
	connectTimeout: 15 * 1000
});


function
get_manta_file(manta, path, callback)
{
	mod_assert.object(manta, 'manta');
	mod_assert.string(path, 'path');
	mod_assert.func(callback, 'callback');

	manta.get(path, function (err, res) {
		if (err) {
			if (err.name === 'ResourceNotFoundError') {
				callback(null, false);
			} else {
				callback(err);
			}
			return;
		}

		var data = '';
		res.on('readable', function () {
			for (;;) {
				var ch = res.read();
				if (!ch)
					return;
				data += ch.toString('utf8');
			}
		});
		res.on('end', function () {
			callback(null, data);
		});
	});
}

function
dfop_check_file(dfop, next)
{
	if (dfop.dfop_retry) {
		next();
		return;
	}

	mod_fs.lstat(dfop.dfop_local_file, function (err, st) {
		if (err) {
			if (err.code === 'ENOENT') {
				PROGBAR.log('"%s" does not exist',
				    mod_path.basename(dfop.dfop_local_file));
				dfop.dfop_download = true;
				next();
				return;
			}

			next(err);
			return;
		}

		if (!st.isFile()) {
			next(new VError('"%s" is not a regular file',
			    dfop.dfop_local_file));
			return;
		}

		if (st.size !== dfop.dfop_expected_size) {
			if (DEBUG) {
				PROGBAR.log(
				    '"%s" size %d, expected %d; unlinking',
				    mod_path.basename(dfop.dfop_local_file),
				    st.size, dfop.dfop_expected_size);
			}
			mod_fs.unlinkSync(dfop.dfop_local_file);
			dfop.dfop_download = true;
			next();
			return;
		}

		next();
	});
}

function
dfop_check_file_md5(dfop, next)
{
	if (dfop.dfop_retry || dfop.dfop_download) {
		next();
		return;
	}

	var summer = mod_crypto.createHash('md5');
	var fstr = mod_fs.createReadStream(dfop.dfop_local_file);
	/*
	 * XXX STREAM ERROR HANDLING
	 */
	fstr.on('readable', function () {
		for (;;) {
			var data = fstr.read(8192);

			if (!data) {
				return;
			}

			summer.update(data);
		}
	});
	fstr.on('end', function () {
		var local_md5 = summer.digest('hex');

		if (local_md5 === dfop.dfop_expected_md5) {
			dfop.dfop_retry = false;
			dfop.dfop_download = false;
			next();
			return;
		}

		PROGBAR.log('"%s" md5 %s, expected %s; unlinking',
		    mod_path.basename(dfop.dfop_local_file),
		    local_md5,
		    dfop.dfop_expected_md5);
		dfop.dfop_download = true;
		next();
	});
}

function
dfop_download_file(dfop, next)
{
	if (dfop.dfop_retry || !dfop.dfop_download) {
		next();
		return;
	}

	PROGBAR.log('download: %s', mod_path.basename(dfop.dfop_local_file));
	PROGBAR.add(dfop.dfop_bit.bit_name, dfop.dfop_expected_size);

	var mstr = MANTA.createReadStream(dfop.dfop_manta_file);
	var fstr = mod_fs.createWriteStream(dfop.dfop_local_file, {
		flags: 'wx',
		mode: 0644
	});

	/*
	 * XXX STREAM ERROR HANDLING
	 */

	var start = Date.now();
	mstr.pipe(fstr);
	mstr.on('data', function (d) {
		PROGBAR.advance(dfop.dfop_bit.bit_name, d.length);
	});
	fstr.on('finish', function () {
		var end = Date.now();
		if (DEBUG) {
			PROGBAR.log('"%s" downloaded in %d seconds',
			    dfop.dfop_bit.bit_name, (end - start) / 1000);
		}
		dfop.dfop_retry = true;
		dfop.dfop_download = false;
		next();
	});
}

/*
 * This function works to ensure that a copy of the selected build artifact
 * exists in the cache directory.  If the artifact exists already, its
 * MD5 sum will be verified.  If the MD5 checksum does not match, the file
 * will be deleted and re-downloaded.  Interrupted downloads will be retried
 * several times.
 */
function
work_download_file(bit, next)
{
	var dfop = {
		dfop_tries: 0,
		dfop_bit: bit,
		dfop_retry: false,
		dfop_download: false,
		dfop_manta_file: bit.bit_manta_file,
		dfop_local_file: mod_path.join(CACHE_DIR,
		    mod_path.basename(bit.bit_manta_file)),
		dfop_expected_size: bit.bit_manta_size,
		dfop_expected_md5: bit.bit_md5sum
	};

	var do_try = function () {
		mod_vasync.pipeline({
			funcs: [
				dfop_check_file,
				dfop_check_file_md5,
				dfop_download_file
			],
			arg: dfop
		}, function (err) {
			if (err) {
				next(err);
				return;
			}

			if (dfop.dfop_retry) {
				dfop.dfop_tries++;
				if (DEBUG) {
					PROGBAR.log('retrying "%s" time %d',
					    mod_path.basename(
					    dfop.dfop_local_file),
					    dfop.dfop_tries);
				}
				dfop.dfop_retry = false;
				setTimeout(do_try, 1000);
				return;
			}

			bit.bit_local_file = dfop.dfop_local_file;
			PROGBAR.log('ok:       %s',
			    mod_path.basename(dfop.dfop_local_file));
			next();
		});
	};

	setImmediate(do_try);
}

function
work_find_build_file(bit, next)
{
	mod_assert.object(bit.bit_file, 'bit_file');
	mod_assert.string(bit.bit_file.base, 'bit_file.base');
	mod_assert.string(bit.bit_file.ext, 'bit_file.ext');
	mod_assert.string(bit.bit_branch, 'bit_branch');
	mod_assert.string(bit.bit_manta_dir, 'bit_manta_dir');

	/*
	 * Build artifacts from MG are uploaded into Manta in a directory
	 * structure that reflects the branch and build stamp, e.g.
	 *
	 *   /Joyent_Dev/public/builds/sdcboot/master-20150421T175549Z
	 *
	 * The build artifact we are interested in downloading generally
	 * has a filename of the form:
	 *
	 *   <base>-<branch>-*.<extension>
	 *
	 * For example:
	 *
	 *   sdcboot-master-20150421T175549Z-g41a555a.tgz
	 *
	 * Build a regular expression that will, given our selection
	 * constraints, match only the build artifact file we are looking for:
	 */
	var fnre = new RegExp([
		'^',
		bit.bit_file.base,
		'-',
		bit.bit_branch,
		'-.*\\.',
		bit.bit_file.ext,
		'$'
	].join(''));

	/*
	 * Walk the build artifact directory for this build run:
	 */
	MANTA.ftw(bit.bit_manta_dir, {
		name: fnre,
		type: 'o'
	}, function (err, res) {
		if (err) {
			next(new VError(err, 'could not find build file'));
			return;
		}

		var count = 0;
		var ent = null;

		res.on('entry', function (obj) {
			count++;
			if (ent !== null) {
				return;
			}

			ent = mod_path.join('/', obj.parent, obj.name);
		});

		res.once('end', function () {
			if (count !== 1) {
				next(new VError('found %d entries, expected 1',
				    count));
				return;
			}

			/*
			 * Store the full Manta path of the build object
			 * for subsequent tasks:
			 */
			bit.bit_manta_file = ent;

			next();
			return;
		});
	});
}

/*
 * When bits are built from MG, a manifest file ("md5sums.txt") is uploaded
 * that includes the MD5 checksum and the filename of each produced bit.  The
 * lines look roughly like:
 *
 *   a28033c7b101328f3f9921a178088c45 bits//sdcboot/sdcboot-g41a555a.tgz
 *
 * It is probably not safe to infer anything about the path, other than
 * that the _basename_ (e.g. "sdcboot-g41a555a.tgz" in the above) will
 * match the uploaded object name in Manta.
 */
function
work_get_md5sum(bit, next)
{
	mod_assert.string(bit.bit_manta_dir, 'bit_manta_dir');
	mod_assert.string(bit.bit_manta_file, 'bit_manta_file');

	/*
	 * Load the manifest file, "md5sums.txt", from the Manta build
	 * directory:
	 */
	var md5name = mod_path.join(bit.bit_manta_dir, 'md5sums.txt');
	get_manta_file(MANTA, md5name, function (err, data) {
		if (err) {
			next(new VError(err, 'failed to fetch md5sums'));
			return;
		}

		if (data === false) {
			next(new VError('md5sum file "%s" not found',
			    md5name));
			return;
		}

		var lines = data.toString().trim().split(/\n/);
		for (var i = 0; i < lines.length; i++) {
			var l = lines[i].split(/ +/);
			var bp = mod_path.basename(l[1]);
			var lookfor = mod_path.basename(bit.bit_manta_file);

			if (bp === lookfor) {
				bit.bit_md5sum = l[0].trim();
				next();
				return;
			}
		}

		next(new VError('no digest in file "%s" for "%s"',
		    md5name, bit.bit_manta_file.base));
	});
}

/*
 * Manta maintains an MD5 checksum for each uploaded object that we can query
 * without downloading the file.  We check that this MD5 checksum matches the
 * expected value from the manifest before downloading.
 */
function
work_check_manta_md5sum(bit, next)
{
	mod_assert.string(bit.bit_manta_file, 'bit_manta_file');
	mod_assert.string(bit.bit_md5sum, 'bit_md5sum');

	MANTA.info(bit.bit_manta_file, function (err, info) {
		if (err) {
			next(new VError(err, 'could not get info about "%s"',
			    bit.bit_manta_file));
			return;
		}

		mod_assert.string(info.md5, 'info.md5');
		mod_assert.number(info.size, 'info.size');

		/*
		 * Manta MD5 sums are BASE64-encoded.  We must convert it
		 * to a hex string for comparison with the manifest value.
		 */
		bit.bit_manta_md5sum = new Buffer(
		    info.md5, 'base64').toString('hex');
		bit.bit_manta_size = info.size;

		if (bit.bit_md5sum === bit.bit_manta_md5sum) {
			next();
			return;
		}

		next(new VError('Manta MD5 "%s" did not match manifest ' +
		    'MD5 "%s"', bit.bit_manta_md5sum, bit.bit_md5sum));
	});
}

/*
 * Each build artifact from MG is uploaded into a Manta directory, e.g.
 *
 *   /Joyent_Dev/public/builds/sdcboot/master-20150421T175549Z
 *
 * MG also maintains an object (not a directory) that contains the full
 * path of the most recent build for a particular branch, e.g.
 *
 *   /Joyent_Dev/public/builds/sdcboot/master-latest
 *
 * This worker function accepts a base Manta path as the first parameter
 * so that it may be partially applied to multiple Manta paths in the
 * same pipeline via Function#bind().
 */
function
work_lookup_latest_dir(base_path, bit, next)
{
	mod_assert.string(base_path, 'base_path');
	mod_assert.object(bit, 'bit');
	mod_assert.func(next, 'next');
	mod_assert.string(bit.bit_jobname, 'bit_jobname');
	mod_assert.string(bit.bit_branch, 'bit_branch');

	/*
	 * Look up the "-latest" pointer file for this branch in Manta:
	 */
	var latest_dir = mod_path.join('/', base_path, bit.bit_jobname,
	    bit.bit_branch + '-latest');
	get_manta_file(MANTA, latest_dir, function (err, data) {
		if (err) {
			next(new VError(err, 'failed to look up latest dir'));
			return;
		}

		if (data === false) {
			next(new VError('latest link "%s" not found',
			    latest_dir));
			return;
		}

		/*
		 * Store the selected Manta build directory that we consider
		 * to be the latest build, for use in subsequent tasks.
		 */
		bit.bit_manta_dir = data.trim();
		next();
	});
}

function
work_make_symlink(bit, next)
{
	mod_assert.string(bit.bit_local_file, 'bit_local_file');
	mod_assert.optionalString(bit.bit_make_symlink, 'bit_make_symlink');

	if (!bit.bit_make_symlink) {
		next();
		return;
	}

	var link_path = mod_path.resolve(mod_path.join(CACHE_DIR,
	    bit.bit_make_symlink));

	try {
		mod_fs.unlinkSync(link_path);
	} catch (err) {
		if (err.code !== 'ENOENT') {
			next(new VError(err, 'unlink "%s" failed', link_path));
			return;
		}
	}

	mod_fs.symlinkSync(mod_path.basename(bit.bit_local_file),
	    link_path);

	next();
}

var FAILURES = [];
var FINAL = {};

var WORK_QUEUE = mod_vasync.queuev({
	worker: function (bit, next) {
		mod_vasync.pipeline({
			funcs: [
				work_lookup_latest_dir.bind(null,
				    build_spec('manta-base-path')),
				work_find_build_file,
				work_get_md5sum,
				work_check_manta_md5sum,
				work_download_file,
				work_make_symlink
			],
			arg: bit
		}, function (err) {
			if (err) {
				PROGBAR.log('ERROR: bit "%s" failed: %s',
				    bit.bit_name, err.message);
				FAILURES.push({
					failure_bit: bit,
					failure_err: err
				});
				next(err);
				return;
			}

			FINAL[bit.bit_name] = bit;
			next();
		});
	},
	concurrency: 50
});
WORK_QUEUE.on('end', function () {
	var hrt = process.hrtime(EPOCH);
	var delta = Math.floor((hrt[0] * 1000) + (hrt[1] / 1000000));

	PROGBAR.end();
	printf('queue end; runtime %d ms\n', delta);

	if (FAILURES.length > 0) {
		printf('failures: %s\n', mod_util.inspect(FAILURES,
		    false, 10, true));
		process.exit(1);
	}
	process.exit(0);
});


function
main()
{
	var opts = parse_opts(process.argv);

	GLOBAL.branch = build_spec('bits-branch');
	printf('%-25s %s\n', 'Bits Branch:', GLOBAL.branch);

	CACHE_DIR = mod_path.resolve(mod_path.join(process.cwd(), opts.cache));

	WORK_QUEUE.push(all_bits(BITS_JSON));
	WORK_QUEUE.close();
}

main();
