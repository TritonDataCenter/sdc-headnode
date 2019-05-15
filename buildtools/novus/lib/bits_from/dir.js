/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019, Joyent, Inc.
 */

var mod_path = require('path');
var mod_fs = require('fs');

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_common = require('../common');

var VError = mod_verror.VError;

function
bits_from_dir(out, bfd, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.object(bfd, 'bfd');
	mod_assert.func(next, 'next');

	mod_vasync.pipeline({
		arg: bfd,
		funcs: [
			bfd_find_build_files
		]
	}, function (err) {
		if (err) {
			next(new VError(err, 'could not get from bits-dir'));
			return;
		}

		mod_assert.arrayOfObject(bfd.bfd_files, 'bfd_files');

		for (var i = 0; i < bfd.bfd_files.length; i++) {
			var mf = bfd.bfd_files[i];

			mod_assert.object(mf, 'mf');
			mod_assert.string(mf.mf_path, 'path');
			mod_assert.string(mf.mf_name, 'name');
			mod_assert.string(mf.mf_ext, 'ext');
			mod_assert.optionalObject(mf.mf_bit_json, 'bit_json');

			var bn = mod_path.basename(mf.mf_path);

			var bit = {
				bit_type: 'file',
				bit_name: mf.mf_name,
				bit_local_file: lib_common.cache_path(bn),
				bit_source_file: mf.mf_path,
				bit_make_symlink: [
					bfd.bfd_prefix,
					'.',
					mf.mf_ext
				].join('')
			};
			if (mf.mf_bit_json) {
				bit.bit_json = mf.mf_bit_json;
			}
			out.push(bit);
		}

		next();
	});
}

function
bfd_find_build_files(bfd, next)
{
	mod_assert.object(bfd, 'bfd');
	mod_assert.arrayOfObject(bfd.bfd_files, 'bfd_files');
	mod_assert.string(bfd.bfd_branch, 'bfd_branch');
	mod_assert.string(bfd.bfd_dir, 'bfd_dir');
	mod_assert.func(next, 'next');

	/*
	 * Build artefacts are arranged in a simple directory structure
	 * during the configure step, e.g.
	 *
	 * ${SOURCE_BITS_DIR}/
	 *     sapi/
	 *         sapi-zfs-master-20150421T182802Z-g983d6be.zfs.gz
	 *
	 * The build artefact we are interested in copying generally
	 * has a filename of the form:
	 *
	 *   <base>-<branch>-*.<extension>
	 *
	 * For example:
	 *
	 *   boot-master-20181203T230136Z.tgz
	 *
	 * Build a regular expression that will, given our selection
	 * constraints, match only the build artefact file we are looking for:
	 */
	var patterns = [];
	for (var i = 0; i < bfd.bfd_files.length; i++) {
		var f = bfd.bfd_files[i];

		mod_assert.string(f.base, 'f.base');
		mod_assert.string(f.ext, 'f.ext');
		mod_assert.string(f.name, 'f.name');
		mod_assert.optionalString(f.symlink_ext, 'f.symlink_ext');
		mod_assert.optionalBool(f.get_bit_json, 'f.get_bit_json');

		patterns.push({
			p_re: new RegExp([
				'^',
				f.base,
				'-',
				bfd.bfd_branch,
				'-.*\\.',
				f.ext,
				'$'
			].join('')),
			p_ents: [],
			p_base: f.base,
			p_ext: f.ext,
			p_symlink_ext: f.symlink_ext,
			p_name: f.name,
			p_get_bit_json: f.get_bit_json
		});
	}

	var check_patterns = function (parent, name) {
		for (var i = 0; i < patterns.length; i++) {
			var p = patterns[i];

			if (p.p_re.test(name)) {
				var fp = mod_path.join('/', parent, name);

				if (p.p_ents.indexOf(fp) === -1) {
					p.p_ents.push(fp);
				}
			}
		}
	};

	/*
	 * Walk the build artefact directory for this build run:
	 */
	mod_fs.readdir(bfd.bfd_dir, function (err, ents) {
		var i;
		var files = [];

		if (err) {
			next(new VError(err, 'could not search for build ' +
			    'files'));
			return;
		}

		for (i = 0; i < ents.length; i++) {
			check_patterns(bfd.bfd_dir, ents[i]);
		}

		var base_version = null;
		for (i = 0; i < patterns.length; i++) {
			var p = patterns[i];

			/*
			 * Select the "latest" build artefact by sorting the
			 * array of filenames.  This is emphatically _not_ our
			 * best foot forward.
			 */
			p.p_ents.sort();

			if (p.p_ents.length < 1) {
				next(new VError('pattern "%s" in dir ' +
				    '"%s" matched %d entries, expected >= 1',
				    p.p_re.toString(),
				    bfd.bfd_dir,
				    p.p_ents.length));
				return;
			}

			var fp = p.p_ents[p.p_ents.length - 1];
			var bn = mod_path.basename(fp);

			var base_re = new RegExp([
				'^(.*)\\.',
				p.p_ext,
				'$'
			].join(''));
			var m = base_re.exec(bn);

			if (base_version === null) {
				base_version = m[1];
			} else if (base_version !== m[1]) {
				next(new VError('mismatched base version in ' +
				    'two files: "%s" and "%s"',
				    base_version,
				    m[1]));
				return;
			}

			var mf = {
				mf_name: p.p_name,
				mf_path: p.p_ents[p.p_ents.length - 1],
				mf_ext: p.p_symlink_ext || p.p_ext
			};

			if (p.p_get_bit_json) {
				var data = mod_fs.readFileSync(mf.mf_path,
				    {encoding: 'utf8'});
				try {
					mf.mf_bit_json = JSON.parse(data);
				} catch (parse_err) {
					next(new VError(parse_err,
					    '"%s" is not JSON', mf.mf_path));
					return;
				}
			}

			files.push(mf);
		}

		bfd.bfd_files = files;

		next();
		return;
	});
}

module.exports = bits_from_dir;
