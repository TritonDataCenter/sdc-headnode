/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_crypto = require('crypto');
var mod_fs = require('fs');
var mod_path = require('path');
var mod_util = require('util');

var mod_assert = require('assert-plus');
var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_manta = require('manta');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_multi_progbar = require('../lib/multi_progbar');
var lib_buildspec = require('../lib/buildspec');

var lib_common = require('../lib/common');
var lib_bits_from_manta = require('../lib/bits_from/manta');
var lib_bits_from_image = require('../lib/bits_from/image');

var VError = mod_verror.VError;

/*
 * Globals:
 */
var SPEC;
var MANTA;
var EPOCH = process.hrtime();

var PROGBAR = new lib_multi_progbar.MultiProgressBar();

var G = {
	branch: 'master',
	features: {},
	concurrency: 50
};

var DEBUG = process.env.DEBUG ? true : false;

function
generate_options()
{
	var options = [
		{
			group: 'General Options'
		},
		{
			names: [ 'dryrun', 'n' ],
			type: 'bool',
			help: [
				'Resolve and print an object describing',
				'the set of bits to download, but do not',
				'download any bits.'
			].join(' ')
		},
		{
			names: [ 'help', 'h' ],
			type: 'bool',
			help: 'Print this help and exit'
		},
		{
			group: 'Manta Options'
		}
	].concat(mod_manta.DEFAULT_CLI_OPTIONS.filter(function (a) {
		if ((a.names.indexOf('help') !== -1) ||
		    (a.names.indexOf('verbose') !== -1)) {
			return (false);
		}

		return (true);
	}));

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
	};

	var opts;
	try {
		opts = parser.parse(argv);
	} catch (ex) {
		errprintf('ERROR: %s', ex.stack);
		usage(1);
	}

	if (opts.help) {
		usage(0);
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
bit_enum_zone(out, name, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.string(name, 'name');
	mod_assert.func(next, 'next');

	var zone_spec = function (key, optional) {
		return (SPEC.get('zones|' + name + '|' + key, optional));
	};

	var source = zone_spec('source', true) || 'manta';
	var jobname = zone_spec('jobname', true) || name;
	var branch = zone_spec('branch', true) || G.branch;

	var base_path = SPEC.get('manta-base-path');
	var alt_base_var = zone_spec('alt_manta_base', true);
	if (alt_base_var) {
		base_path = SPEC.get(alt_base_var);
	}

	switch (source) {
	case 'manta':
		var basen = jobname + '-zfs';
		lib_bits_from_manta(out, {
			bfm_manta: MANTA,
			bfm_prefix: 'zone.' + name,
			bfm_jobname: jobname,
			bfm_branch: branch,
			bfm_files: [
				{ name: name + '_manifest',
				    base: basen, ext: 'imgmanifest' },
				{ name: name + '_image',
				    base: basen, ext: 'zfs.gz' }
			],
			bfm_base_path: base_path
		}, next);
		return;

	case 'imgapi':
		lib_bits_from_image(out, {
			bfi_prefix: 'zone.' + name,
			bfi_imgapi: 'https://updates.joyent.com',
			bfi_uuid: zone_spec('uuid'),
			bfi_name: jobname
		}, next);
		return;

	default:
		next(new VError('unsupported "zone" source "%s"', source));
		return;
	}
}

function
bit_enum_image(out, name, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.string(name, 'name');
	mod_assert.func(next, 'next');

	var image_spec = function (key, optional) {
		return (SPEC.get('images|' + name + '|' + key, optional));
	};

	var source = image_spec('source', true) || 'imgapi';

	switch (source) {
	case 'imgapi':
		lib_bits_from_image(out, {
			bfi_prefix: 'image.' + name,
			bfi_imgapi: image_spec('imgapi'),
			bfi_uuid: image_spec('uuid'),
			bfi_version: image_spec('version'),
			bfi_name: image_spec('name')
		}, next);
		return;

	default:
		next(new VError('unsupported "image" source "%s"', source));
		return;
	}
}

function
bit_enum_file(out, name, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.string(name, 'name');
	mod_assert.func(next, 'next');

	var file_spec = function (key, optional) {
		return (SPEC.get('files|' + name + '|' + key, optional));
	};

	var source = file_spec('source', true) || 'manta';
	var jobname = file_spec('jobname', true) || name;
	var branch = file_spec('branch', true) || G.branch;

	var base_path = SPEC.get('manta-base-path');
	var alt_base_var = file_spec('alt_manta_base', true);
	if (alt_base_var) {
		base_path = SPEC.get(alt_base_var);
	}

	switch (source) {
	case 'manta':
		lib_bits_from_manta(out, {
			bfm_manta: MANTA,
			bfm_prefix: 'file.' + name,
			bfm_jobname: jobname,
			bfm_branch: branch,
			bfm_files: [
				{
					name: name,
					base: file_spec('file|base'),
					ext: file_spec('file|ext')
				}
			],
			bfm_base_path: base_path
		}, next);
		return;

	default:
		next(new VError('unsupported "file" source "%s"', source));
		return;
	}
}

function
process_artifacts(callback)
{
	mod_assert.func(callback, 'callback');

	var out = [];

	var process_artifact_type = function (_, done) {
		mod_assert.object(_, '_');
		mod_assert.string(_.type, '_.type');
		mod_assert.func(_.func, '_.func');

		mod_vasync.forEachParallel({
			inputs: SPEC.keys(_.type),
			func: function (name, next) {
				var if_feature = SPEC.get(_.type + '|' + name +
				    '|if_feature', true);
				var not_feature = SPEC.get(_.type + '|' + name +
				    '|if_not_feature', true);

				if ((if_feature &&
				    !G.features[if_feature]) ||
				    (not_feature &&
				    G.features[not_feature])) {
					next();
					return;
				}

				_.func(out, name, function (err) {
					if (!err) {
						next();
						return;
					}

					next(new VError(err, 'processing ' +
					    '%s "%s"', _.type, name));
				});
			}
		}, done);
	};

	mod_vasync.forEachParallel({
		inputs: [
			{ type: 'zones', func: bit_enum_zone },
			{ type: 'files', func: bit_enum_file },
			{ type: 'images', func: bit_enum_image }
		],
		func: process_artifact_type
	}, function (err) {
		if (err) {
			callback(new VError(err, 'enumeration of build ' +
			    'artifacts failed'));
			return;
		}

		callback(null, out);
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

	var start = Date.now();
	lib_common.get_via_http(dfop.dfop_url, function (err, res) {
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
		dfop.dfop_local_file = lib_common.cache_path(mod_path.basename(
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
		    'MD5 "%s"', bit.bit_manta_md5sum, bit.bit_hash));
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

	var link_path = lib_common.cache_path(bit.bit_make_symlink);

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
			next(new VError(ex, 'could not unlink "%s"',
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

		mod_assert.object(bit, 'bit');
		mod_assert.string(bit.bit_type, 'bit.bit_type');
		mod_assert.string(bit.bit_local_file, 'bit.bit_local_file');

		switch (bit.bit_type) {
		case 'manta':
			funcs = [
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
	concurrency: G.concurrency
});
WORK_QUEUE.on('end', function () {
	var hrt = process.hrtime(EPOCH);
	var delta = Math.floor((hrt[0] * 1000) + (hrt[1] / 1000000));

	PROGBAR.end();
	errprintf('queue end; runtime %d ms\n', delta);

	if (FAILURES.length > 0) {
		errprintf('failures: %s\n', mod_util.inspect(FAILURES,
		    false, 10, true));
		process.exit(1);
	}
	process.exit(0);
});

function
create_manta_client(opts)
{
	var override = function (key, opt) {
		var v = SPEC.get(key, true);

		if (v) {
			opts[opt] = v;
		}
	};

	override('manta-user', 'account');
	override('manta-subuser', 'subuser');
	override('manta-url', 'url');
	override('manta-key-id', 'keyId');

	if (process.env.MANTA_NO_AUTH) {
		opts.noAuth = true;
	} else {
		opts.sign = mod_manta.cliSigner({
			algorithm: opts.algorithm,
			keyId: opts.keyId,
			user: opts.account,
			subuser: opts.subuser
		});
	}

	opts.connectTimeout = 15 * 1000;

	return (mod_manta.createClient(opts));
}

function
main()
{
	var opts = parse_opts(process.argv);

	lib_buildspec.load_build_specs(lib_common.root_path('build.spec'),
	    lib_common.root_path('build.spec.local'), function (err, bs) {
		var i;

		if (err) {
			console.error('ERROR loading build specs: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		MANTA = create_manta_client(opts);

		var fts = SPEC.keys('features');
		for (i = 0; i < fts.length; i++) {
			G.features[fts[i]] = !!SPEC.get('features|' +
			    fts[i]);
		}

		var evs = SPEC.keys('environment');
		for (i = 0; i < evs.length; i++) {
			if (process.env.hasOwnProperty(evs[i])) {
				G.features[fts[i]] = true;
			}
		}

		G.branch = SPEC.get('bits-branch');
		errprintf('%-25s %s\n', 'Bits Branch:', G.branch);

		errprintf('%-25s %s\n', 'Features:',
		    Object.keys(G.features).filter(function (k) {
			    return (!!G.features[k]);
		    }).join(', '));

		process_artifacts(function (err, bits) {
			if (err) {
				console.error('ERROR: enumerating bits: %s',
				    err.stack);
				process.exit(3);
			}

			if (opts.dryrun) {
				console.log(JSON.stringify(bits));
				process.exit(0);
			}

			errprintf('pushing bits to work queue...\n');
			WORK_QUEUE.push(bits);
			WORK_QUEUE.close();
		});
	});
}

main();
