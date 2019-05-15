/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 */

var mod_path = require('path');

var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');

var lib_common = require('../lib/common');
var lib_buildspec = require('../lib/buildspec');

/*
 * Globals:
 */
var SPEC;

var VALID_TYPES = [
	'zones',
	'images',
	'files'
];

function
generate_options()
{
	var options = [
		{
			names: [ 'feature', 'f' ],
			type: 'bool',
			help: 'Check if this feature is enabled'
		},
		{
			names: [ 'list-artefacts', 'a' ],
			type: 'bool',
			help: [
				'List artefacts for artefact type.',
				'Valid types:',
				VALID_TYPES.join(', ') + '.'
			].join(' ')
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
	};

	var opts;
	try {
		opts = parser.parse(argv);
	} catch (ex) {
		errprintf('ERROR: %s', ex.stack);
		usage(1);
	}

	if (opts._args.length !== 1) {
		errprintf('ERROR: must provide feature name');
		usage(1);
	}
	opts.name = opts._args[0];

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
main()
{
	var opts = parse_opts(process.argv);

	lib_buildspec.load_build_spec(
			lib_common.root_path('build.spec.merged'),
			function (err, bs) {
		if (err) {
			console.error('ERROR loading build spec: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		if (opts.feature) {
			console.log(SPEC.feature(opts.name));
		} else if (opts.list_artefacts) {
			console.log(SPEC.keys(opts.name).join('\n'));
		} else {
			console.log(SPEC.get(opts.name));
		}

		process.exit(0);
	});
}

main();
