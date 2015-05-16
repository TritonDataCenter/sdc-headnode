#!/usr/bin/env node
/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_crypto = require('crypto');
var mod_fs = require('fs');
var mod_path = require('path');
var mod_util = require('util');
var mod_http = require('http');
var mod_https = require('https');
var mod_url = require('url');

var mod_assert = require('assert-plus');
var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_jsprim = require('jsprim');
var mod_manta = require('manta');
var mod_vasync = require('vasync');
var mod_verror = require('verror');
var mod_readtoend = require('readtoend');

var lib_multi_progbar = require('../lib/multi_progbar');
var lib_buildspec = require('../lib/buildspec');

var VError = mod_verror.VError;

/*
 * Globals:
 */
var SPEC;
var MANTA;
var EPOCH = process.hrtime();

var PROGBAR = new lib_multi_progbar.MultiProgressBar();

var CACHE_DIR;
var BITS_JSON = require('../../../bits.json');
var GLOBAL = {
	branch: 'master'
};


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
cache_path(relpath)
{
	return (mod_path.resolve(mod_path.join(CACHE_DIR, relpath)));
}

function
get_via_http(url_str, callback)
{
	mod_assert.string(url_str, 'url_str');
	mod_assert.func(callback, 'callback');

	var opts = mod_url.parse(url_str);
	var mod_proto = (opts.protocol === 'https:') ? mod_https : mod_http;

	var req = mod_proto.request(opts, function (res) {
		if (res.statusCode !== 200) {
			callback(new VError('http status %d invalid for "%s"',
			    res.statusCode, url_str));
			return;	
		}

		callback(null, res);
	});

	req.on('error', function (err) {
		callback(new VError(err, 'http error for "%s"', url_str));
	});

	req.end();
}

function
get_json_via_http(url_str, callback)
{
	get_via_http(url_str, function (err, res) {
		if (err) {
			callback(err);
			return;
		}

		var rs = mod_readtoend.readToEnd(res, function (_err,
		    body) {
			if (_err) {
				callback(new VError(_err, 'error reading ' +
				    'JSON response from "%s"', url_str));
				return;
			}

			var obj;
			try {
				obj = JSON.parse(body);
			} catch (ex) {
				callback(new VError(ex, 'error parsing ' +
				    'JSON response from "%s"', url_str));
				return;
			}

			callback(null, obj);
		});
	});
}

function
bit_enum_image(out, _, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.object(_, '_');
	mod_assert.func(next, 'next');
	mod_assert.string(_.name, '_.name');
	mod_assert.object(_.params, '_.params');
	mod_assert.string(_.params.imgapi, '_.params.imgapi');
	mod_assert.string(_.params.name, '_.params.name');
	mod_assert.string(_.params.version, '_.params.version');
	mod_assert.string(_.params.uuid, '_.params.uuid');

	var name = _.params.name;
	var version = _.params.version;
	var uuid = _.params.uuid;
	var url = [
		_.params.imgapi,
		'images',
		_.params.uuid
	].join('/');

	get_json_via_http(url, function (err, img) {
		if (err) {
			next(new VError(err, 'could not get image "%s"',
			    uuid));
			return;
		}

		/*
		 * This image must have exactly one file:
		 */
		if (!img.files || img.files.length !== 1) {
			next(new VError('invalid image "%s"', uuid));
			return;
		}

		var fil = img.files[0];
		mod_assert.string(fil.sha1, 'file.sha1');
		mod_assert.number(fil.size, 'file.size');
		mod_assert.string(fil.compression, 'file.compression');

		/*
		 * Make sure our "name" and "version" match those of the image
		 * we looked up by "uuid":
		 */
		if (img.name !== name || img.version !== version) {
			next(new VError('upstream image identity ' +
			    '"%s-%s" did not match expected ' +
			    '"%s-%s"', img.name, img.version,
			    name, version));
			return;
		}

		/*
		 * Create a synthetic "download" request that will write the
		 * manifest object we just loaded to the appropriate cache
		 * file.
		 */
		out.push({
			bit_type: 'json',
			bit_name: _.name + '_manifest',
			bit_local_file: cache_path([
				name,
				'-',
				version,
				'.dsmanifest'
			].join('')),
			bit_json: img,
			bit_make_symlink: [
				'image.',
				_.name,
				'.dsmanifest'
			].join('')
		});

		/*
		 * Create a download request for the image file:
		 */
		out.push({
			bit_type: 'http',
			bit_name: _.name + '_image',
			bit_local_file: cache_path([
				name,
				'-',
				version,
				'.zfs.',
				fil.compression === 'bzip2' ?  'bz2' : 'gz'
			].join('')),
			bit_url: url + '/file',
			bit_hash_type: 'sha1',
			bit_hash: fil.sha1,
			bit_size: fil.size,
			bit_make_symlink: [
				'image.',
				_.name,
				'.zfs.',
				fil.compression === 'bzip2' ?  'bz2' : 'gz'
			].join('')
		});

		next();
	});
}

function
all_bits(input, callback)
{
	var out = [];
	var keys;

	mod_assert.object(input.zones, 'zones');
	mod_assert.object(input.bits, 'bits');
	mod_assert.object(input.images, 'images');

	/*
	 * Load the list of zones from the configuration, generating a bit
	 * record for each of the manifest and the image of each zone.
	 */
	keys = Object.keys(input.zones || {});
	for (var i = 0; i < keys.length; i++) {
		var name = keys[i];
		var zone = input.zones[name];

		out.push({
			bit_type: 'manta',
			bit_name: name + '_manifest',
			bit_branch: zone.branch || GLOBAL.branch,
			bit_jobname: zone.jobname || name,
			bit_file: {
				base: (zone.jobname || name) + '-zfs',
				ext: 'imgmanifest'
			},
			bit_make_symlink: 'zone.' + name + '.imgmanifest'
		});
		out.push({
			bit_type: 'manta',
			bit_name: name + '_image',
			bit_branch: zone.branch || GLOBAL.branch,
			bit_jobname: zone.jobname || name,
			bit_file: {
				base: (zone.jobname || name) + '-zfs',
				ext: 'zfs.gz'
			},
			bit_make_symlink: 'zone.' + name + '.zfs.gz'
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
			bit_type: 'manta',
			bit_name: name,
			bit_branch: bit.branch || GLOBAL.branch,
			bit_jobname: bit.jobname || name,
			bit_file: {
				base: bit.file.base,
				ext: bit.file.ext
			},
			bit_make_symlink: 'bit.' + name + '.' + bit.file.ext
		});
	}

	/*
	 * Lookup images, specified by uuid, in imgapi:
	 */
	mod_vasync.forEachParallel({
		func: function (name, next) {
			bit_enum_image(out, {
				name: name,
				params: input.images[name]
			}, next);
		},
		inputs: Object.keys(input.images)
	}, function (err) {
		if (err) {
			callback(new VError(err, 'imgapi lookup failed'));
			return;
		}

		callback(null, out);
	});
}



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
				if (DEBUG) {
					PROGBAR.log('"%s" does not exist',
					    mod_path.basename(
					    dfop.dfop_local_file));
				}
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
dfop_check_file_checksum(dfop, next)
{
	mod_assert.object(dfop, 'dfop');
	mod_assert.string(dfop.dfop_hash_type, 'hash_type');
	mod_assert.string(dfop.dfop_hash, 'hash');
	mod_assert.func(next, 'next');

	if (dfop.dfop_retry || dfop.dfop_download) {
		next();
		return;
	}

	var summer = mod_crypto.createHash(dfop.dfop_hash_type);

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
		var local_hash = summer.digest('hex');

		if (local_hash === dfop.dfop_hash) {
			dfop.dfop_retry = false;
			dfop.dfop_download = false;
			next();
			return;
		}

		PROGBAR.log('"%s" hash = %s, expected %s; unlinking',
		    mod_path.basename(dfop.dfop_local_file),
		    local_hash,
		    dfop.dfop_hash);
		mod_fs.unlinkSync(dfop.dfop_local_file);
		dfop.dfop_download = true;
		next();
	});
}

function
dfop_download_file_http(dfop, next)
{
	if (dfop.dfop_retry || !dfop.dfop_download) {
		next();
		return;
	}

	PROGBAR.log('download: %s', mod_path.basename(dfop.dfop_local_file));
	PROGBAR.add(dfop.dfop_bit.bit_name, dfop.dfop_expected_size);

	get_via_http(dfop.dfop_url, function (err, res) {
		if (err) {
			next(err);
			return;
		}

		var fstr = mod_fs.createWriteStream(dfop.dfop_local_file, {
			flags: 'wx',
			mode: 0644
		});
		res.pipe(fstr);
		/*
		 * XXX STREAM ERROR HANDLING
		 */
		res.on('data', function (d) {
			PROGBAR.advance(dfop.dfop_bit.bit_name, d.length);
		});
		fstr.on('finish', function () {
			var end = Date.now();
			if (DEBUG) {
				PROGBAR.log('"%s" downloaded in %d seconds',
				    dfop.dfop_bit.bit_name,
				    (end - start) / 1000);
			}
			dfop.dfop_retry = true;
			dfop.dfop_download = false;
			next();
		});
	});
}

function
dfop_download_file_manta(dfop, next)
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
	mod_assert.string(bit.bit_hash_type, 'bit_hash_type');
	mod_assert.string(bit.bit_hash, 'bit_hash');

	var dfop = {
		dfop_tries: 0,
		dfop_bit: bit,
		dfop_retry: false,
		dfop_download: false,
		dfop_expected_size: bit.bit_size,
		dfop_local_file: bit.bit_local_file,
		dfop_hash: bit.bit_hash,
		dfop_hash_type: bit.bit_hash_type
	};

	var funcs;

	switch (bit.bit_type) {
	case 'manta':
		mod_assert.number(dfop.dfop_expected_size,
		    'dfop_expected_size');
		mod_assert.string(bit.bit_manta_file, 'bit_manta_file');

		dfop.dfop_manta_file = bit.bit_manta_file;
		dfop.dfop_local_file = cache_path(mod_path.basename(
		    bit.bit_manta_file));

		funcs = [
			dfop_check_file,
			dfop_check_file_checksum,
			dfop_download_file_manta
		];
		break;

	case 'http':
		mod_assert.number(dfop.dfop_expected_size,
		    'dfop_expected_size');
		mod_assert.string(bit.bit_url, 'bit_url');

		dfop.dfop_url = bit.bit_url;

		funcs = [
			dfop_check_file,
			dfop_check_file_checksum,
			dfop_download_file_http
		];
		break;

	default:
		next(new VError('invalid bit type "%s"', bit.bit_type));
		return;
	}

	var do_try = function () {
		mod_vasync.pipeline({
			funcs: funcs,
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
				bit.bit_hash_type = 'md5';
				bit.bit_hash = l[0].trim();
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
	mod_assert.string(bit.bit_hash, 'bit_hash');
	mod_assert.strictEqual(bit.bit_hash_type, 'md5');
	mod_assert.string(bit.bit_manta_file, 'bit_manta_file');

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
		bit.bit_size = info.size;

		if (bit.bit_hash === bit.bit_manta_md5sum) {
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

function
work_write_json_to_file(bit, next)
{
	mod_assert.strictEqual(bit.bit_type, 'json');
	mod_assert.string(bit.bit_local_file, 'bit_local_file');
	mod_assert.object(bit.bit_json, 'bit_json');

	var out = JSON.stringify(bit.bit_json);
	try {
		mod_fs.unlinkSync(bit.bit_local_file);
	} catch (ex) {
		if (ex.code !== 'ENOENT') {
			next(new VError(err, 'could not unlink "%s"',
			    bit.bit_local_file));
			return;
		}
	}

	mod_fs.writeFile(bit.bit_local_file, out, {
		encoding: 'utf8',
		mode: 0644,
		flag: 'wx'
	}, function (err) {
		if (err) {
			next (new VError(err, 'could not write file "%s"',
			    bit.bit_local_file));
			return;
		}

		next();
	});
}

var FAILURES = [];
var FINAL = {};

var WORK_QUEUE = mod_vasync.queuev({
	worker: function (bit, next) {
		var funcs;

		switch (bit.bit_type) {
		case 'manta':
			funcs = [
				work_lookup_latest_dir.bind(null,
				    SPEC.get('manta-base-path')),
				work_find_build_file,
				work_get_md5sum,
				work_check_manta_md5sum,
				work_download_file,
				work_make_symlink
			];
			break;

		case 'json':
			funcs = [
				work_write_json_to_file,
				work_make_symlink
			];
			break;

		case 'http':
			funcs = [
				work_download_file,
				work_make_symlink
			];
			break;

		default:
			FAILURES.push({
				failure_bit: bit,
				failure_err: new VError('invalid bit ' +
				    'type "%s"', bit.bit_type)
			});
			next();
			return;
		}

		mod_vasync.pipeline({
			funcs: funcs,
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

			PROGBAR.log('ok:       %s', bit.bit_name);

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
root_path(path)
{
	return (mod_path.resolve(mod_path.join(__dirname, '..', '..', '..',
	    path)));
}

function
main()
{
	var opts = parse_opts(process.argv);

	CACHE_DIR = mod_path.resolve(mod_path.join(process.cwd(), opts.cache));

	lib_buildspec.load_build_specs(root_path('build.spec'),
	    root_path('build.spec.local'), function (err, bs) {
		if (err) {
			console.error('ERROR loading build specs: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		GLOBAL.branch = SPEC.get('bits-branch');
		printf('%-25s %s\n', 'Bits Branch:', GLOBAL.branch);

		MANTA = mod_manta.createClient({
			user: SPEC.get('manta-user'),
			url: SPEC.get('manta-url'),
			connectTimeout: 15 * 1000
		});

		all_bits(BITS_JSON, function (err, bits) {
			if (err) {
				console.error('ERROR enumerating bits: %s',
				    err.stack);
				process.exit(3);
			}

			printf('pushing bits to work queue...\n');
			WORK_QUEUE.push(bits);
			WORK_QUEUE.close();
		});
	});

}

main();
