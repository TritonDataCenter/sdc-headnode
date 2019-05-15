/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 */

var mod_fs = require('fs');
var mod_path = require('path');
var mod_util = require('util');

var mod_assert = require('assert-plus');
var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_manta = require('manta');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_common = require('../lib/common');
var lib_multi_progbar = require('../lib/multi_progbar');
var lib_buildspec = require('../lib/buildspec');
var lib_workq = require('../lib/workq');

var lib_bits_from_manta = require('../lib/bits_from/manta');
var lib_bits_from_image = require('../lib/bits_from/image');
var lib_bits_from_dir = require('../lib/bits_from/dir');

var VError = mod_verror.VError;

/*
 * Globals:
 */
var DEBUG = process.env.DEBUG ? true : false;

function
generate_options()
{
	var options = [
		{
			group: 'Download Options'
		},
		{
			names: [ 'write-manifest', 'w' ],
			type: 'string',
			help: [
				'Write a JSON object describing each',
				'discovered build artefact to the named',
				'file.  If the value "-" is passed, the',
				'output will be directed to stdout.'
			].join(' '),
			helpArg: 'FILE'
		},
		{
			names: [ 'download', 'd' ],
			type: 'bool',
			help: [
				'Download the resolved build artefacts and',
				'update the current artefact symlink for each.'
			].join(' ')
		},
		{
			names: [ 'clean-cache', 'c' ],
			type: 'bool',
			help: [
				'Once all files are downloaded, remove any',
				'old cache files that are no longer',
				'in use.'
			].join(' ')
		},
		{
			group: 'General Options'
		},
		{
			names: [ 'no-progbar', 'N' ],
			type: 'bool',
			help: [
				'Disable progress bar.  Note that the progress',
				'bar will be disabled automatically if there',
				'is no controlling terminal.'
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
bit_enum_assert(be, next)
{
	mod_assert.object(be, 'be');
	mod_assert.arrayOfObject(be.be_out, 'be.be_out');
	mod_assert.object(be.be_manta, 'be.be_manta');
	mod_assert.object(be.be_spec, 'be.be_spec');
	mod_assert.string(be.be_name, 'be.be_name');
	mod_assert.string(be.be_default_branch, 'be.be_default_branch');
	mod_assert.func(next, 'next');
}

/*
 * Gather the bits for this zone image. However, do *not* append them to
 * `be.be_out`. Instead they are returned via the `next` callback:
 * `next(null, out)`.
 */
function
bit_enum_zone(be, next) {
	bit_enum_assert(be, next);

	var bits;
	var name = be.be_name;
	var zone_spec = function (key, optional) {
		return (be.be_spec.get('zones|' + name + '|' + key, optional));
	};

	var source = be.be_override_source || zone_spec('source', true) ||
	    'manta';
	var jobname = zone_spec('jobname', true) || name;
	var branch = zone_spec('branch', true) ||
	    be.be_default_branch;

	var base_path = be.be_spec.get('manta-base-path');
	var alt_base_var = zone_spec('alt_manta_base', true);
	if (alt_base_var) {
		base_path = be.be_spec.get(alt_base_var);
	}

	switch (source) {
	case 'manta':
		bits = [];
		lib_bits_from_manta(bits, {
			bfm_manta: be.be_manta,
			bfm_prefix: 'zone.' + name,
			bfm_jobname: jobname,
			bfm_branch: branch,
			bfm_files: [
				{
					name: name + '_imgmanifest',
					base: jobname + '-zfs',
					ext: 'imgmanifest',
					get_bit_json: true
				},
				{
					name: name + '_imgfile',
					base: jobname + '-zfs',
					ext: 'zfs.gz',
					symlink_ext: 'imgfile'
				}
			],
			bfm_base_path: base_path
		}, function on_manta_bits(err) {
			if (err) {
				next(err);
				return;
			}

			/*
			 * Append `bits` to `be.be_out` and gather any
			 * origin images.
			 */
			var img;
			bits.forEach(function push_bit(bit) {
				be.be_out.push(bit);
				if (bit.bit_name === name + '_imgmanifest') {
					img = bit.bit_json;
				}
			});
			mod_assert.object(img, 'img manifest');

			if (img.origin) {
				lib_common.origin_bits_from_updates(be.be_out, {
					obfu_origin_uuid: img.origin
				}, next);
			} else {
				next();
			}
		});
		return;

	case 'imgapi':
		lib_bits_from_image(be.be_out, {
			bfi_prefix: 'zone.' + name,
			bfi_imgapi: 'https://updates.joyent.com',
			bfi_uuid: zone_spec('uuid'),
			bfi_channel: zone_spec('channel', true),
			bfi_name: jobname
		}, next);
		return;

	case 'bits-dir':
		/*
		 * bits-dir uses a directory layout mirroring our Manta uploads.
		 */
		mod_assert.string(
			process.env.SOURCE_BITS_DIR, '$SOURCE_BITS_DIR');

		 var bits_from_dir = mod_path.join(
			process.env.SOURCE_BITS_DIR,
			jobname, branch + '-latest', jobname);

		bits = [];
		lib_bits_from_dir(bits, {
			bfd_dir: bits_from_dir,
			bfd_prefix: 'zone.' + name,
			bfd_jobname: jobname,
			bfd_branch: branch,
			bfd_files: [
				{
					name: name + '_imgmanifest',
					base: jobname + '-zfs',
					ext: 'imgmanifest',
					get_bit_json: true
				},
				{
					name: name + '_imgfile',
					base: jobname + '-zfs',
					ext: 'zfs.gz',
					symlink_ext: 'imgfile'
				}
			]
		}, function on_dir_bits(err) {
			if (err) {
				next(err);
				return;
			}

			/*
			 * Append `bits` to `be.be_out` and gather any
			 * origin images.
			 */
			var img;
			bits.forEach(function push_bit(bit) {
				be.be_out.push(bit);
				if (bit.bit_name === name + '_imgmanifest') {
					img = bit.bit_json;
				}
			});
			mod_assert.object(img, 'img manifest');

			if (img.origin) {
				lib_common.origin_bits_from_updates(be.be_out, {
					obfu_origin_uuid: img.origin
				}, next);
			} else {
				next();
			}
		});
		return;

	default:
		next(new VError('unsupported "zone" source "%s"', source));
		return;
	}
}

function
bit_enum_file(be, next)
{
	bit_enum_assert(be, next);

	var name = be.be_name;
	var file_spec = function (key, optional) {
		return (be.be_spec.get('files|' + name + '|' + key, optional));
	};

	var source = be.be_override_source || file_spec('source', true) ||
	    'manta';
	var jobname = file_spec('jobname', true) || name;
	var branch = file_spec('branch', true) ||
	    be.be_default_branch;

	switch (source) {
	case 'manta':
		var base_path = be.be_spec.get('manta-base-path');
		var alt_base_var = file_spec('alt_manta_base', true);
		if (alt_base_var) {
			base_path = be.be_spec.get(alt_base_var);
		}
		var timestamp = 'latest';
		var build_timestamp = file_spec('build_timestamp', true);
		if (build_timestamp) {
			timestamp = build_timestamp;
		}
		lib_bits_from_manta(be.be_out, {
			bfm_manta: be.be_manta,
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
			bfm_base_path: base_path,
			bfm_timestamp: timestamp
		}, next);
		return;

	case 'bits-dir':
		mod_assert.string(
			process.env.SOURCE_BITS_DIR, '$SOURCE_BITS_DIR');

		/*
		 * bits-dir uses a directory layout mirroring our Manta uploads.
		 */
		var bits_from_dir = mod_path.join(
			process.env.SOURCE_BITS_DIR,
			jobname, branch + '-latest', jobname);

		lib_bits_from_dir(be.be_out, {
			bfd_dir: bits_from_dir,
			bfd_prefix: 'file.' + name,
			bfd_jobname: jobname,
			bfd_branch: branch,
			bfd_files: [
				{
					name: name,
					base: file_spec('file|base'),
					ext: file_spec('file|ext')
				}
			]
		}, next);
		return;

	default:
		next(new VError('unsupported "file" source "%s"', source));
		return;
	}
}

function
process_artefacts(pa, callback)
{
	mod_assert.object(pa, 'pa');
	mod_assert.object(pa.pa_manta, 'pa.pa_manta');
	mod_assert.object(pa.pa_spec, 'pa.pa_spec');
	mod_assert.string(pa.pa_default_branch, 'pa.pa_default_branch');
	mod_assert.func(callback, 'callback');

	var out = [];

	var override_source = pa.pa_spec.get('override-all-sources',
	    true) || false;

	/*
	 * Enumerate all build artefacts of a particular artefact type:
	 */
	var process_artefact_type = function (_, done) {
		mod_assert.object(_, '_');
		mod_assert.string(_.type, '_.type');
		mod_assert.func(_.func, '_.func');

		mod_vasync.forEachParallel({
			inputs: pa.pa_spec.keys(_.type),
			func: function (name, next) {
				var if_f = pa.pa_spec.get(_.type + '|' +
				    name + '|if_feature', true);
				var not_f = pa.pa_spec.get(_.type + '|' +
				    name + '|if_not_feature', true);

				/*
				 * If a feature conditional was specified, but
				 * the condition is not met, skip out
				 */
				if ((if_f && !pa.pa_spec.feature(if_f)) ||
				    (not_f && pa.pa_spec.feature(not_f))) {
					next();
					return;
				}

				_.func({
					be_out: out,
					be_manta: pa.pa_manta,
					be_spec: pa.pa_spec,
					be_name: name,
					be_default_branch: pa.pa_default_branch,
					be_override_source: override_source
				}, function (err) {
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

	/*
	 * Process each of the different build artefact types:
	 */
	mod_vasync.forEachParallel({
		inputs: [
			{ type: 'zones', func: bit_enum_zone },
			{ type: 'files', func: bit_enum_file }
		],
		func: process_artefact_type
	}, function (err) {
		if (err) {
			callback(new VError(err, 'enumeration of build ' +
			    'artefacts failed'));
			return;
		}

		callback(null, out);
	});
}

function
clean_cache(dryrun, active_files)
{
	mod_assert.bool(dryrun, 'dryrun');
	mod_assert.arrayOfString(active_files, 'active_files');

	var ents = mod_fs.readdirSync(lib_common.cache_path(''));
	for (var i = 0; i < ents.length; i++) {
		var bn = ents[i];
		var fp = lib_common.cache_path(bn);
		var st = mod_fs.lstatSync(fp);

		if (st.isFile() && active_files.indexOf(bn) === -1) {
			if (DEBUG) {
				errprintf('orphan file: %s\n', bn);
			}

			if (!dryrun) {
				mod_fs.unlinkSync(fp);
			}
		}
	}
}

function
create_manta_client(spec, opts)
{
	var override = function (key, opt) {
		var v = spec.get(key, true);

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

	var bar = new lib_multi_progbar.MultiProgressBar({
		progbar: !opts.no_progbar
	});

	lib_buildspec.load_build_spec(
			lib_common.root_path('build.spec.merged'),
			function (err, bs) {
		if (err) {
			console.error('ERROR: loading build spec: %s',
			    err.stack);
			process.exit(3);
		}

		var spec = bs;
		var manta = create_manta_client(spec, opts);
		var workq = new lib_workq.WorkQueue({
			concurrency: 50,
			progbar: bar,
			manta: manta
		});

		var default_branch = spec.get('bits-branch');
		bar.log('%-25s %s', 'Default Branch:', default_branch);

		var start = process.hrtime();
		bar.log('enumerating build artefacts...');
		process_artefacts({
			pa_default_branch: default_branch,
			pa_manta: manta,
			pa_spec: spec
		}, function (err, bits) {
			if (err) {
				console.error('ERROR: enumerating bits: %s',
				    err.stack);
				process.exit(3);
			}

			bar.log('enumeration complete (%d ms; %d artefacts)',
			    lib_common.delta_ms(start), bits.length);

			var wmf = opts.write_manifest;
			if (wmf) {
				var out = JSON.stringify(bits);

				if (wmf === '-') {
					console.log(out);
				} else {
					mod_fs.writeFileSync(wmf, out);
				}
			}

			if (!opts.download) {
				bar.log('skipping download; run complete.');
				process.exit(0);
			}

			bar.log('downloading missing artefacts...');
			workq.push(bits);
			workq.close();

			workq.on('end', function () {
				if (workq.wq_failures.length > 0) {
					errprintf('ERROR: failures: %s\n',
					    mod_util.inspect(workq.wq_failures,
					    false, 10, true));
					process.exit(1);
				}

				if (spec.get('clean-cache', true) ||
				    opts.clean_cache) {
					errprintf('cleaning cache...\n');
					clean_cache(false,
					    workq.wq_active_files);
				}

				errprintf('done!\n');
				process.exit(0);
			});
		});
	});
}

main();
