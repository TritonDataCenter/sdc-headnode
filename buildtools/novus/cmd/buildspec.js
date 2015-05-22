/* vim: set ts=8 sts=8 sw=8 noet: */

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
			names: [ 'list-artifacts', 'a' ],
			type: 'bool',
			help: [
				'List artifacts for artifact type.',
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

	lib_buildspec.load_build_specs(lib_common.root_path('build.spec'),
	    lib_common.root_path('build.spec.local'), function (err, bs) {
		if (err) {
			console.error('ERROR loading build specs: %s',
			    err.stack);
			process.exit(3);
		}

		SPEC = bs;

		if (opts.feature) {
			console.log(SPEC.feature(opts.name));
		} else if (opts.list_artifacts) {
			console.log(SPEC.keys(opts.name).join('\n'));
		} else {
			console.log(SPEC.get(opts.name));
		}

		process.exit(0);
	});
}

main();
