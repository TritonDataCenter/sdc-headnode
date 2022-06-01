/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2017 Joyent, Inc.
 * Copyright 2022 MNX Cloud, Inc.
 */

var mod_path = require('path');
var mod_http = require('http');
var mod_https = require('https');
var mod_url = require('url');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');
var mod_readtoend = require('readtoend');

var VError = mod_verror.VError;

function
delta_ms(hrt_epoch)
{
	var delta = process.hrtime(hrt_epoch);

	return (Math.floor(delta[0] * 1000 + delta[1] / 1000000));
}

function
get_via_http(url_str, headers, callback)
{
	mod_assert.string(url_str, 'url_str');
	mod_assert.object(headers, 'headers');
	mod_assert.func(callback, 'callback');

	var opts = mod_url.parse(url_str);
	var mod_proto = (opts.protocol === 'https:') ? mod_https : mod_http;
	opts.headers = headers;

	var req = mod_proto.request(opts, function (res) {
		if (res.statusCode !== 200) {
			callback(new VError('http status %d invalid for "%s"',
			    res.statusCode, url_str));
			return;
		}

		callback(null, res);
	});

	req.on('error', function (err) {
		callback(new VError(err, 'http error for "%s"', url_str));
	});

	req.end();
}

function
get_json_via_http(url_str, headers, callback)
{
	get_via_http(url_str, headers, function (err, res) {
		if (err) {
			callback(err);
			return;
		}

		mod_readtoend.readToEnd(res, function (_err, body) {
			if (_err) {
				callback(new VError(_err, 'error reading ' +
				    'JSON response from "%s"', url_str));
				return;
			}

			var obj;
			try {
				obj = JSON.parse(body);
			} catch (ex) {
				callback(new VError(ex, 'error parsing ' +
				    'JSON response from "%s"', url_str));
				return;
			}

			callback(null, obj);
		});
	});
}

function
get_manta_file(manta, path, callback)
{
	mod_assert.object(manta, 'manta');
	mod_assert.string(path, 'path');
	mod_assert.func(callback, 'callback');

	manta.get(path, function (err, res) {
		if (err) {
			if (err.name === 'ResourceNotFoundError') {
				callback(null, false);
			} else {
				callback(err);
			}
			return;
		}

		var data = '';
		res.on('readable', function () {
			for (;;) {
				var ch = res.read();
				if (!ch)
					return;
				data += ch.toString('utf8');
			}
		});
		res.on('end', function () {
			callback(null, data);
		});
	});
}

function
cache_path(relpath)
{
	return (mod_path.join(root_path('cache'), relpath));
}

function
root_path(path)
{
	return (mod_path.resolve(mod_path.join(__dirname, '..', '..', '..',
	    path)));
}


/*
 * Append "bit_enum" objects (see downloader.js "bit_enum_*" functions) to
 * `out`: one for each image in the given `obfu_origin_uuid`'s ancestry.
 */
function
origin_bits_from_updates(out, obfu, next)
{
	mod_assert.arrayOfObject(out, 'out');
	mod_assert.object(obfu, 'obfu');
	mod_assert.string(obfu.obfu_origin_uuid, 'obfu.obfu_origin_uuid');
	mod_assert.func(next, 'next');

	var origin_uuid = obfu.obfu_origin_uuid;
	var url = 'https://updates.tritondatacenter.com/images/' + origin_uuid;
	var query = '?channel=*';

	get_json_via_http(url + query, {
		'Accept-Version': '~2' // Need IMGAPI v2 to get "channels".
	}, function on_img(err, img) {
		if (err) {
			next(new VError(err, 'could not get image "%s"',
			    origin_uuid));
			return;
		}

		mod_assert.arrayOfString(img.channels, 'img.channels');
		var channel = img.channels[0];
		delete img.channels; // Don't want "channels" field for USB key.

		/*
		 * This image must have exactly one file:
		 */
		if (!img.files || img.files.length !== 1) {
			next(new VError(
			    'invalid image "%s": other than 1 file',
			    origin_uuid));
			return;
		}

		/*
		 * Many images can share this origin. If this is already in
		 * our download list, then we are done.
		 */
		var bit_name = origin_uuid + '_imgmanifest';
		var have_it = out.some(function (rec) {
			return rec.bit_name === bit_name;
		});
		if (have_it) {
			next();
			return;
		}

		var fil = img.files[0];
		mod_assert.string(fil.sha1, 'file.sha1');
		mod_assert.number(fil.size, 'file.size');
		mod_assert.string(fil.compression, 'file.compression');

		/*
		 * Create a synthetic "download" request that will write the
		 * manifest object we just loaded to the appropriate cache
		 * file.
		 */
		out.push({
			bit_type: 'json',
			bit_name: origin_uuid + '_imgmanifest',
			bit_local_file: cache_path(
			    origin_uuid + '.imgmanifest'),
			bit_json: img,
			bit_make_symlink: 'image.' + origin_uuid +
			    '.imgmanifest'
		});

		/*
		 * Create a download request for the image file:
		 */
		out.push({
			bit_type: 'http',
			bit_name: origin_uuid + '_imgfile',
			bit_local_file: cache_path(origin_uuid + '.imgfile'),
			bit_url: url + '/file?channel=' + channel,
			bit_hash_type: 'sha1',
			bit_hash: fil.sha1,
			bit_size: fil.size,
			bit_make_symlink: 'image.' + origin_uuid + '.imgfile'
		});

		/*
		 * Walk the ancestry (origin chain) for this image and create
		 * download requests for them (if not already in `out`).
		 */
		if (img.origin) {
			origin_bits_from_updates(out, {
				obfu_origin_uuid: img.origin
			}, next);
		} else {
			next();
		}
	});
}


module.exports = {
	root_path: root_path,
	cache_path: cache_path,
	get_via_http: get_via_http,
	get_json_via_http: get_json_via_http,
	get_manta_file: get_manta_file,
	delta_ms: delta_ms,
	origin_bits_from_updates: origin_bits_from_updates
};
