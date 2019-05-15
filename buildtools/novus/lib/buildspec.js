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

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var VError = mod_verror.VError;

var NAMES_TRUE = [
	'yes',
	'y',
	'1',
	'true'
];
var NAMES_FALSE = [
	'no',
	'n',
	'0',
	'false'
];

function
env_to_boolean(varname, value_if_missing)
{
	mod_assert.string(varname, 'varname');
	mod_assert.optionalBool(value_if_missing, 'value_if_missing');

	if (!process.env.hasOwnProperty(varname) ||
	    process.env[varname] === '') {
		/*
		 * The variable was not set in the environment, or was set
		 * to the empty string.
		 */
		if (value_if_missing === true ||
		    value_if_missing === false) {
			return (value_if_missing);
		}

		throw (new VError('environment variable %s was not set',
		    varname));
	}

	var v = process.env[varname].trim().toLowerCase();

	if (NAMES_TRUE.indexOf(v) !== -1) {
		return (true);
	} else if (NAMES_FALSE.indexOf(v) !== -1) {
		return (false);
	} else {
		throw (new VError('value "%s" is not valid for environment ' +
		    'variable %s', v, varname));
	}
}

function
pluck(o, name)
{
	var c = name.split(/\|/);

	return (plucka(o, c));
}

function
plucka(o, components)
{
	if (components.length === 0) {
		return (o);
	}

	var top = components.shift();
	if (!o.hasOwnProperty(top)) {
		return (undefined);
	}

	return (plucka(o[top], components));
}

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
		var val = pluck(spec.spec_object, name);

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

/*
 * The equivalent of `Object.keys(name)`, but applied to all specs in the
 * stack.  Consumers are expected to get a list of keys with this function,
 * and then look up the intended values via get().  For example:
 *
 *	var zones = SPEC.keys('zones');
 *	zones.forEach(function (zone) {
 *		var jobname = SPEC.get('zones|' + zone + '|jobname');
 *	});
 *
 * This pattern allows a higher priority spec to override a specific
 * value nested within the tree without copying the entire structure.
 */
BuildSpec.prototype.keys = function
keys(name)
{
	mod_assert.string(name, 'name');

	var self = this;
	var out = [];

	for (var i = 0; i < self.bs_specs.length; i++) {
		var spec = self.bs_specs[i];
		var val = pluck(spec.spec_object, name);

		if (!val || typeof (val) !== 'object') {
			continue;
		}

		var vk = Object.keys(val);
		for (var j = 0; j < vk.length; j++) {
			if (out.indexOf(vk[j]) === -1) {
				out.push(vk[j]);
			}
		}
	}

	out.sort();
	return (out);
};

/*
 * Determine whether or not the named feature is active for this build.  The
 * default value is loaded from the build specification file(s).  If the
 * feature definition nominates an environment variable, and that variable is
 * set, we allow that value to override the build specification.
 */
BuildSpec.prototype.feature = function
feature(name)
{
	var self = this;

	if (self.keys('features').indexOf(name) === -1) {
		throw (new VError('feature "%s" not found in build ' +
		    'specification', name));
	}

	var enabled = self.get('features|' + name + '|enabled');
	var envname = self.get('features|' + name + '|env', true);

	mod_assert.bool(enabled, 'features|' + name + '|enabled');
	mod_assert.optionalString(envname, 'features|' + name + '|env');

	if (typeof (envname) !== 'string') {
		/*
		 * This feature does not have an associated environment
		 * variable.
		 */
		return (enabled);
	}

	return (env_to_boolean(envname, enabled));
};

module.exports = {
	load_build_spec: function (base_file, cb) {
		mod_assert.string(base_file, 'base_file');
		mod_assert.func(cb, 'cb');

		var bs = new BuildSpec();

		bs.load_file(base_file, false, function (err) {
			cb(err, bs);
		});
	}
};
