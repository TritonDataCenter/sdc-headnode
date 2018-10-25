/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2018 Joyent, Inc.
 */

var mod_path = require('path');

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_common = require('../common');

var VError = mod_verror.VError;

function
bits_from_manta(out, bfm, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.object(bfm, 'bfm');
	mod_assert.func(next, 'next');
	mod_vasync.pipeline({
		arg: bfm,
		funcs: [
			bfm_lookup_latest_dir,
			bfm_get_md5sum,
			bfm_find_build_files
		]
	}, function (err) {
		if (err) {
			next(new VError(err, 'could not get from manta'));
			return;
		}
		mod_assert.object(bfm.bfm_manta_hashes, 'bfm_manta_hashes');
		mod_assert.arrayOfObject(bfm.bfm_manta_files,
		    'bfm_manta_files');

		for (var i = 0; i < bfm.bfm_manta_files.length; i++) {
			var mf = bfm.bfm_manta_files[i];

			mod_assert.object(mf, 'mf');
			mod_assert.string(mf.mf_path, 'path');
			mod_assert.string(mf.mf_name, 'name');
			mod_assert.string(mf.mf_ext, 'ext');
			mod_assert.optionalObject(mf.mf_bit_json, 'bit_json');

			var bn = mod_path.basename(mf.mf_path);
			var hash = bfm.bfm_manta_hashes[bn];

			if (!hash) {
				next(new VError('could not find hash in ' +
				    '"md5sums.txt" for "%s"', bn));
				return;
			}

			var bit = {
				bit_type: 'manta',
				bit_name: mf.mf_name,
				bit_local_file: lib_common.cache_path(bn),
				bit_manta_file: mf.mf_path,
				bit_hash_type: 'md5',
				bit_hash: hash,
				bit_make_symlink: [
					bfm.bfm_prefix,
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
bfm_find_build_files(bfm, next)
{
	mod_assert.object(bfm, 'bfm');
	mod_assert.object(bfm.bfm_manta, 'bfm.bfm_manta');
	mod_assert.arrayOfObject(bfm.bfm_files, 'bfm_files');
	mod_assert.string(bfm.bfm_branch, 'bfm_branch');
	mod_assert.string(bfm.bfm_manta_dir, 'bfm_manta_dir');
	mod_assert.func(next, 'next');

	/*
	 * Build artefacts from MG are uploaded into Manta in a directory
	 * structure that reflects the branch and build stamp, e.g.
	 *
	 *   /Joyent_Dev/public/builds/sdcboot/master-20150421T175549Z
	 *
	 * The build artefact we are interested in downloading generally
	 * has a filename of the form:
	 *
	 *   <base>-<branch>-*.<extension>
	 *
	 * For example:
	 *
	 *   sdcboot-master-20150421T175549Z-g41a555a.tgz
	 *
	 * Build a regular expression that will, given our selection
	 * constraints, match only the build artefact file we are looking for:
	 */
	var patterns = [];
	for (var i = 0; i < bfm.bfm_files.length; i++) {
		var f = bfm.bfm_files[i];

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
				bfm.bfm_branch,
				'-.*\\.',
				f.ext,
				'$'
			].join('')),
			p_count: 0,
			p_ent: null,
			p_base: f.base,
			p_ext: f.ext,
			p_symlink_ext: f.symlink_ext,
			p_name: f.name,
			p_get_bit_json: Boolean(f.get_bit_json)
		});
	}

	var check_patterns = function (parent, name) {
		for (var i = 0; i < patterns.length; i++) {
			var p = patterns[i];

			if (p.p_re.test(name)) {
				if (!p.p_ent) {
					p.p_ent = mod_path.join('/', parent,
					    name);
				}
				p.p_count++;
			}
		}
	};

	var mf_from_pattern = function (p, next_p)
	{
		mod_assert.object(p, 'pattern');
		mod_assert.func(next_p, 'next_p');

		if (p.p_count !== 1) {
			next_p(new VError('pattern "%s" matched %d entries, ' +
			    'expected 1', p.p_re.toString(), p.p_count));
			return;
		}

		var mf = {
			mf_name: p.p_name,
			mf_path: p.p_ent,
			mf_ext: p.p_symlink_ext || p.p_ext,
		};

		/*
		 * If requested, download and parse the Manta file as JSON.
		 */
		if (!p.p_get_bit_json) {
			next_p(null, mf);
		} else {
			lib_common.get_manta_file(bfm.bfm_manta, p.p_ent,
			    function got_manta_file(err, data) {
				if (err) {
					next_p(err);
					return;
				} else if (data === false) {
					next_p(new VError('"%s" not found',
					    p.p_ent));
					return;
				}
				try {
					mf.mf_bit_json = JSON.parse(data);
				} catch (parse_err) {
					next_p(new VError(parse_err,
					    '"%s" is not JSON', p.p_ent));
					return;
				}
				next_p(null, mf);
			});
		}
	};

	/*
	 * Walk the build artefact directory for this build run:
	 */
	bfm.bfm_manta.ftw(bfm.bfm_manta_dir, {
		type: 'o'
	}, function (err, res) {
		if (err) {
			next(new VError(err, 'could not search for build ' +
			    'files'));
			return;
		}

		res.on('entry', function (obj) {
			check_patterns(obj.parent, obj.name);
		});

		res.once('end', function () {
			mod_vasync.forEachParallel({
				inputs: patterns,
				func: mf_from_pattern
			}, function checked_patterns(err, results) {
				if (err) {
					next(new VError(err, 'could not ' +
					    'find matching Manta files in ' +
					    'dir "%s"', bfm.bfm_manta_dir));
					return;
				}

				/*
				 * Store the full Manta path(s) of the build
				 * object for subsequent tasks:
				 */
				bfm.bfm_manta_files = results.successes;

				next();
			});

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
bfm_get_md5sum(bfm, next)
{
	mod_assert.object(bfm, 'bfm');
	mod_assert.object(bfm.bfm_manta, 'bfm_manta');
	mod_assert.string(bfm.bfm_manta_dir, 'bfm_manta_dir');

	/*
	 * Load the manifest file, "md5sums.txt", from the Manta build
	 * directory:
	 */
	var md5name = mod_path.join(bfm.bfm_manta_dir, 'md5sums.txt');
	lib_common.get_manta_file(bfm.bfm_manta, md5name, function (err, data) {
		if (err) {
			next(new VError(err, 'failed to fetch md5sums'));
			return;
		}

		if (data === false) {
			next(new VError('md5sum file "%s" not found',
			    md5name));
			return;
		}

		var path_to_md5 = {};

		var lines = data.toString().trim().split(/\n/);
		for (var i = 0; i < lines.length; i++) {
			var l = lines[i].split(/ +/);
			if (l.length !== 2) {
				continue;
			}

			var bp = mod_path.basename(l[1]);
			if (path_to_md5[bp]) {
				next(new VError('file "%s" contains two ' +
				    'hashes for "%s"', md5name, bp));
				return;
			}

			path_to_md5[bp] = l[0].trim().toLowerCase();
		}

		bfm.bfm_manta_hashes = path_to_md5;
		next();
	});
}

/*
 * Each build artefact from MG is uploaded into a Manta directory, e.g.
 *
 *   /Joyent_Dev/public/builds/sdcboot/master-20150421T175549Z
 *
 * MG also maintains an object (not a directory) that contains the full
 * path of the most recent build for a particular branch, e.g.
 *
 *   /Joyent_Dev/public/builds/sdcboot/master-latest
 */
function
bfm_lookup_latest_dir(bfm, next)
{
	mod_assert.object(bfm, 'bfm');
	mod_assert.object(bfm.bfm_manta, 'bfm_manta');
	mod_assert.string(bfm.bfm_base_path, 'bfm_base_path');
	mod_assert.string(bfm.bfm_jobname, 'bfm_jobname');
	mod_assert.string(bfm.bfm_branch, 'bfm_branch');
	mod_assert.optionalString(bfm.bfm_timestamp, 'bfm_timestamp');
	mod_assert.func(next, 'next');


	/*
	 * Look up the "-latest" pointer file for this branch in Manta:
	 */
	if (!bfm.bfm_timestamp) {
		bfm.bfm_timestamp = 'latest';
	}
	var latest_dir = mod_path.join('/', bfm.bfm_base_path,
	    bfm.bfm_jobname, bfm.bfm_branch + '-' + bfm.bfm_timestamp);
	if (bfm.bfm_timestamp !== 'latest') {
		bfm.bfm_manta_dir = latest_dir;
		next();
		return;
	}
	lib_common.get_manta_file(bfm.bfm_manta, latest_dir,
	    function (err, data) {
		if (err) {
			next(new VError(err, 'failed to look up latest dir'));
			return;
		}

		if (data === false) {
			next(new VError('latest link "%s" not found',
			    latest_dir));
			return;
		}

		bfm.bfm_manta_dir = data.trim();
		next();
	});
}

module.exports = bits_from_manta;
