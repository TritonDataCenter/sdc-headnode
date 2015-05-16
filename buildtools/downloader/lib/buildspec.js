/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_path = require('path');
var mod_fs = require('fs');

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_verror = require('verror');
var mod_jsprim = require('jsprim');

var VError = mod_verror.VError;

/*
 * Present a merged view of a "stack" of build.spec files.  Files will
 * be consulted for values in reverse of the order in which they are
 * loaded; i.e., the file loaded last will be checked first.
 */
function
BuildSpec()
{
	var self = this;

	self.bs_specs = [];
}

BuildSpec.prototype.load_file = function
load_file(path, optional, cb)
{
	mod_assert.string(path, 'path');
	mod_assert.bool(optional, 'boolean');
	mod_assert.func(cb, 'cb');

	var self = this;

	mod_fs.readFile(path, {
		encoding: 'utf8'
	}, function (err, content) {
		if (optional && err && err.code === 'ENOENT') {
			cb();
			return;
		}

		if (err) {
			cb(new VError(err, 'could not read file "%s"',
			    path));
			return;
		}

		var obj;
		try {
			obj = JSON.parse(content);
		} catch (ex) {
			cb(new VError(err, 'could not parse file "%s"',
			    path));
			return;
		}

		self.bs_specs.unshift({
			spec_path: path,
			spec_object: obj
		});

		cb();
	});
};

BuildSpec.prototype.get = function
get(name, optional)
{
	mod_assert.string(name, 'name');
	mod_assert.optionalBool(optional, 'optional');

	var self = this;

	/*
	 * Files are added to the list with "unshift", i.e. most recent
	 * addition is at index 0.
	 */
	for (var i = 0; i < self.bs_specs.length; i++) {
		var spec = self.bs_specs[i];
		var val = mod_jsprim.pluck(spec.spec_object, name);

		if (val !== undefined) {
			return (val);
		}
	}

	if (optional !== true) {
		throw (new VError('could not find value "%s" in build specs',
		    name));
	}

	return (undefined);
};

module.exports = {
	load_build_specs: function (base_file, optional_file, cb) {
		mod_assert.string(base_file, 'base_file');
		mod_assert.string(optional_file, 'optional_file');
		mod_assert.func(cb, 'cb');

		var bs = new BuildSpec();

		mod_vasync.forEachPipeline({
			func: function (_, next) {
				bs.load_file(_.path, _.optional, next);
			},
			inputs: [
				{ optional: false, path: base_file },
				{ optional: true, path: optional_file }
			]
		}, function (err) {
			if (err) {
				cb(new VError(err, 'failed to load build ' +
				    'specs'));
				return;
			}

			cb(null, bs);
		});
	}
};
