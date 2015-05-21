#!/usr/bin/env node
/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_path = require('path');
var mod_http = require('http');
var mod_https = require('https');
var mod_url = require('url');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');
var mod_readtoend = require('readtoend');

var VError = mod_verror.VError;

function
get_via_http(url_str, callback)
{
	mod_assert.string(url_str, 'url_str');
	mod_assert.func(callback, 'callback');

	var opts = mod_url.parse(url_str);
	var mod_proto = (opts.protocol === 'https:') ? mod_https : mod_http;

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
get_json_via_http(url_str, callback)
{
	get_via_http(url_str, function (err, res) {
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
	return (mod_path.resolve(mod_path.join(__dirname, '..', '..', path)));
}

module.exports = {
	root_path: root_path,
	cache_path: cache_path,
	get_via_http: get_via_http,
	get_json_via_http: get_json_via_http,
	get_manta_file: get_manta_file
};
