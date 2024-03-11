/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 * Copyright 2024 MNX Cloud, Inc.
 */

var mod_fs = require('fs');
var mod_path = require('path');

var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_monowrap = require('monowrap');

var lib_common = require('../lib/common');
var lib_buildspec = require('../lib/buildspec');

/*
 * Globals:
 */
var SPEC;

var ERRORS = [];

function
generate_options()
{
	var options = [
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
	};

	var opts;
	try {
		opts = parser.parse(argv);
	} catch (ex) {
		errprintf('ERROR: %s', ex.stack);
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
check_old_branch_keys()
{
	var OLD_TO_NEW = {
		'platform-image': '"files.platform.*"',
		'platform-release': '"files.platform.*"',
		'ipxe-release': '"files.ipxe.*"',
		'sdcadm-release': '"files.sdcadm.*"',
		'agents-shar': '"files.agents.*" and "files.agents_md5.*"'
	};

	var lines = [];
	var keys = Object.keys(OLD_TO_NEW).sort();
	for (var i = 0; i < keys.length; i++) {
		var key = keys[i];

		if (!SPEC.get(key, true)) {
			continue;
		}

		lines.push('  - "' + key + '" becomes ' + OLD_TO_NEW[key]);
	}

	if (lines.length > 0) {
		ERRORS.push([
			'The following keys are no longer supported, and must',
			'be converted to the new style as described in the',
			'documentation:'
		].join(' ') + '\n\n' + lines.join('\n') + '\n');
	}
}

function
check_features()
{
	var OLD_TO_NEW = {
		'debug-platform': '"features.debug-platform.*" or $DEBUG_BUILD'
	};

	var lines = [];
	var keys = Object.keys(OLD_TO_NEW).sort();
	for (var i = 0; i < keys.length; i++) {
		var key = keys[i];

		if (!SPEC.get(key, true)) {
			continue;
		}

		lines.push('  - "' + key + '" is either ' + OLD_TO_NEW[key]);
	}

	if (lines.length > 0) {
		ERRORS.push([
			'The following keys are no longer supported, and must',
			'be converted to "features" as described in the',
			'documentation:'
		].join(' ') + '\n\n' + lines.join('\n') + '\n');
	}
}

function
check_datasets()
{
	if (!SPEC.get('datasets', true)) {
		return;
	}

	ERRORS.push([
		'The "datasets" key in "build.spec" is no longer supported.',
		'Please see the documentation for the new "image" key.'
	].join(' '));
}

function
is_local_file(val)
{
	try {
		var st = mod_fs.statSync(val);
		if (st.isFile()) {
			return (true);
		}
	} catch (ex) {
	}

	return (false);
}

function
is_uuid(val)
{
	var uuid_re = new RegExp([
		'^',
		'[0-9a-f]{8}-',
		'[0-9a-f]{4}-',
		'[0-9a-f]{4}-',
		'[0-9a-f]{4}-',
		'[0-9a-f]{12}',
		'$'
	].join(''), 'i');

	return (!!uuid_re.test(val));
}

function
check_old_image_specs()
{
	var OLD_KEYS = [
		'adminui',
		'amon',
		'amonredis',
		'assets',
		'binder',
		'cloudapi',
		'cnapi',
		'dhcpd',
		'fwapi',
		'imgapi',
		'mahi',
		'manatee',
		'moray',
		'napi',
		'papi',
		'rabbitmq',
		'sapi',
		'sdc',
		'ufds',
		'vmapi',
		'workflow'
	];
	var OTHER_NAMES = {
		'manatee': 'sdc-manatee',
		'manta': 'manta-deployment'
	};

	var i;
	var msg;
	var newobj;
	var set_to_default = [];
	var other = [];
	var uuids = [];
	var local_files = [];

	for (i = 0; i < OLD_KEYS.length; i++) {
		var k = OLD_KEYS[i];
		var specval = SPEC.get(k + '-image', true);

		if (specval) {
			var job = OTHER_NAMES[k] || k;
			var full = job + '/' + job + '-zfs-.*manifest';

			if (is_local_file(specval)) {
				local_files.push(k);
			} else if (is_uuid(specval)) {
				uuids.push(k);
			} else if (specval === full) {
				set_to_default.push(k);
			} else {
				other.push(k);
			}
		}
	}

	if (set_to_default.length > 0) {
		msg = [
			'The following keys are no longer supported, but',
			'your configuration matches the new defaults.',
			'These keys should be removed:'
		].join(' ') + '\n\n';

		for (i = 0; i < set_to_default.length; i++) {
			msg += '  - "' + set_to_default[i] + '-image"\n';
		}

		msg += '\n';
		ERRORS.push(msg);
	}

	if (local_files.length > 0) {
		msg = [
			'The following keys are no longer supported, but can',
			'be respecified in the new format.  They specify',
			'local files to use directly instead of downloading',
			'from Manta.  First, remove these keys:'
		].join(' ') + '\n\n';

		for (i = 0; i < local_files.length; i++) {
			msg += '  - "' + local_files[i] + '-image"\n';
		}

		msg += '\n' + [
			'Next, specify the same data in the new format:'
		].join(' ') + '\n\n';

		newobj = {
			zones: {}
		};
		for (i = 0; i < local_files.length; i++) {
			newobj.zones[local_files[i]] = {
				source: 'file',
				file: SPEC.get(local_files[i] + '-image')
			};
		}
		msg += JSON.stringify(newobj, false, 4).split('\n').
		    map(function (a) {
			return ('    ' + a);
		}).join('\n');

		msg += '\n';
		ERRORS.push(msg);
	}

	if (uuids.length > 0) {
		msg = [
			'The following keys are no longer supported, but can',
			'be respecified in the new format.  They specify',
			'image UUIDs to download from an IMGAPI',
			'server.  First, remove these keys:'
		].join(' ') + '\n\n';

		for (i = 0; i < uuids.length; i++) {
			msg += '  - "' + uuids[i] + '-image"\n';
		}

		msg += '\n' + [
			'Next, specify the same data in the new format:'
		].join(' ') + '\n\n';

		newobj = {
			zones: {}
		};
		for (i = 0; i < uuids.length; i++) {
			newobj.zones[uuids[i]] = {
				source: 'imgapi',
				imgapi: 'https://updates.tritondatacenter.com',
				uuid: SPEC.get(uuids[i] + '-image')
			};
		}
		msg += JSON.stringify(newobj, false, 4).split('\n').
		    map(function (a) {
			return ('    ' + a);
		}).join('\n');

		msg += '\n';
		ERRORS.push(msg);
	}

	if (other.length > 0) {
		msg = [
			'The following keys are no longer supported, but',
			'your configuration could not be converted',
			'automatically.  Please see the documentation for',
			'the new "zones" key.  The affected keys and their',
			'new counterparts are listed below:'
		].join(' ') + '\n\n';

		for (i = 0; i < other.length; i++) {
			msg += '  - "' + other[i] + '-image" --> ' +
			    '"zones.' + other[i] + '"\n';
		}

		msg += '\n';
		ERRORS.push(msg);
	}
}

function
main()
{
	parse_opts(process.argv);

	lib_buildspec.load_build_spec(
			lib_common.root_path('build.spec.merged'),
			function (err, bs) {
		if (err) {
			console.error('ERROR loading build spec: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		check_old_branch_keys();
		check_features();
		check_datasets();
		check_old_image_specs();

		if (ERRORS.length > 0) {
			console.error(ERRORS.join('\n\n'));
			process.exit(1);
		}

		process.exit(0);
	});
}

main();
