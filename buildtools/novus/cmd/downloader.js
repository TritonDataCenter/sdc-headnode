/* vim: set ts=8 sts=8 sw=8 noet: */

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
var LIB_WORK = {};

var PROGBAR = new lib_multi_progbar.MultiProgressBar();

var G = {
	branch: 'master',
	concurrency: 50
};

function
require_lib_work()
{
	var libdir = mod_path.join(__dirname, '..', 'lib', 'work');
	var ents = mod_fs.readdirSync(libdir);

	for (var i = 0; i < ents.length; i++) {
		var ent = ents[i];
		var m = ent.match(/^(.*)\.js$/);

		if (m) {
			mod_assert.ok(!LIB_WORK[m[1]]);

			LIB_WORK[m[1]] = require(mod_path.join(libdir, ent));
		}
	}
}

function
lib_work(name)
{
	var f = LIB_WORK[name];

	mod_assert.func(f, 'work func "' + name + '"');

	return (f);
}

function
generate_options()
{
	var options = [
		{
			group: 'General Options'
		},
		{
			names: [ 'write-manifest', 'w' ],
			type: 'string',
			help: [
				'Write a JSON object describing each',
				'discovered build artifact to the named',
				'file.  If the value "-" is passed, the',
				'output will be directed to stdout.'
			].join(' ')
		},
		{
			names: [ 'dryrun', 'n' ],
			type: 'bool',
			help: [
				'Resolve the set of build artifacts to',
				'download, but do not actually perform',
				'any downloads or modify the filesystem.'
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
				var if_feat = SPEC.get(_.type + '|' + name +
				    '|if_feature', true);
				var not_feat = SPEC.get(_.type + '|' + name +
				    '|if_not_feature', true);

				/*
				 * If a feature conditional was specified, but
				 * the condition is not met, skip out
				 */
				if ((if_feat && !SPEC.feature(if_feat)) ||
				    (not_feat && SPEC.feature(not_feat))) {
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
				'check_manta_md5sum',
				'download_file',
				'make_symlink'
			];
			break;

		case 'json':
			funcs = [
				'write_json_to_file',
				'make_symlink'
			];
			break;

		case 'http':
			funcs = [
				'download_file',
				'make_symlink'
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
			funcs: funcs.map(lib_work),
			arg: {
				wa_bit: bit,
				wa_manta: MANTA,
				wa_bar: PROGBAR
			}
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

	require_lib_work();

	lib_buildspec.load_build_specs(lib_common.root_path('build.spec'),
	    lib_common.root_path('build.spec.local'), function (err, bs) {
		if (err) {
			console.error('ERROR loading build specs: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		MANTA = create_manta_client(opts);

		G.branch = SPEC.get('bits-branch');
		errprintf('%-25s %s\n', 'Bits Branch:', G.branch);

		var dc = Number(SPEC.get('download-concurrency', true) ||
		    G.concurrency);
		if (isNaN(dc) || dc < 1) {
			errprintf('invalid value "%s" for "build.spec" ' +
			    'key "%s"\n', SPEC.get('download-concurrency'),
			    'download-concurrency');
			process.exit(1);
		}

		PROGBAR.log('enumerating build artifacts...');
		process_artifacts(function (err, bits) {
			if (err) {
				console.error('ERROR: enumerating bits: %s',
				    err.stack);
				process.exit(3);
			}

			PROGBAR.log('enumeration complete');

			var wmf = opts.write_manifest;
			if (wmf) {
				var out = JSON.stringify(bits);

				if (wmf === '-') {
					console.log(out);
				} else {
					mod_fs.writeFileSync(wmf, out);
				}
			}

			if (opts.dryrun) {
				PROGBAR.log('dryrun complete');
				process.exit(0);
			}

			WORK_QUEUE.push(bits);
			WORK_QUEUE.close();
		});
	});
}

main();
