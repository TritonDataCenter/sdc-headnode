/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2015 Joyent, Inc.
 */

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var VError = mod_verror.VError;

var lib_common = require('../common');

/*
 * This function looks up a specific image, by UUID, in an IMGAPI service.
 * The resultant manifest and data file will be inserted into the bits
 * array "out".
 */
function
bits_from_image(out, bfi, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.object(bfi, 'bfi');
	mod_assert.string(bfi.bfi_prefix, 'bfi.bfi_prefix');
	mod_assert.string(bfi.bfi_imgapi, 'bfi.bfi_imgapi');
	mod_assert.string(bfi.bfi_uuid, 'bfi.bfi_uuid');
	mod_assert.string(bfi.bfi_name, 'bfi.bfi_name');
	mod_assert.optionalString(bfi.bfi_version, 'bfi.bfi_version');
	mod_assert.func(next, 'next');

	var uuid = bfi.bfi_uuid;
	var name = bfi.bfi_name || false;
	var version = bfi.bfi_version || false;
	var url = [
		bfi.bfi_imgapi,
		'images',
		bfi.bfi_uuid
	].join('/');

	lib_common.get_json_via_http(url, function (err, img) {
		if (err) {
			next(new VError(err, 'could not get image "%s"',
			    uuid));
			return;
		}

		mod_assert.string(img.name, 'img.name');
		mod_assert.string(img.version, 'img.version');

		/*
		 * This image must have exactly one file:
		 */
		if (!img.files || img.files.length !== 1) {
			next(new VError('invalid image "%s"', uuid));
			return;
		}

		var fil = img.files[0];
		mod_assert.string(fil.sha1, 'file.sha1');
		mod_assert.number(fil.size, 'file.size');
		mod_assert.string(fil.compression, 'file.compression');

		/*
		 * Make sure our "name" and "version" match those of the image
		 * we looked up by "uuid":
		 */
		if ((name !== false && img.name !== name) ||
		    (version !== false && img.version !== version)) {
			next(new VError('upstream image identity ' +
			    '"%s-%s" did not match expected ' +
			    '"%s-%s"', img.name, img.version,
			    name || '*', version || '*'));
			return;
		}

		/*
		 * Create a synthetic "download" request that will write the
		 * manifest object we just loaded to the appropriate cache
		 * file.
		 */
		out.push({
			bit_type: 'json',
			bit_name: name + '_manifest',
			bit_local_file: lib_common.cache_path([
				img.name,
				'-',
				img.version,
				'.imgmanifest'
			].join('')),
			bit_json: img,
			bit_make_symlink: [
				bfi.bfi_prefix,
				'.imgmanifest'
			].join('')
		});

		/*
		 * Create a download request for the image file:
		 */
		out.push({
			bit_type: 'http',
			bit_name: name + '_image',
			bit_local_file: lib_common.cache_path([
				img.name,
				'-',
				img.version,
				'.zfs.',
				fil.compression === 'bzip2' ? 'bz2' : 'gz'
			].join('')),
			bit_url: url + '/file',
			bit_hash_type: 'sha1',
			bit_hash: fil.sha1,
			bit_size: fil.size,
			bit_make_symlink: [
				bfi.bfi_prefix,
				'.zfs.',
				fil.compression === 'bzip2' ? 'bz2' : 'gz'
			].join('')
		});

		next();
	});

}

module.exports = bits_from_image;
