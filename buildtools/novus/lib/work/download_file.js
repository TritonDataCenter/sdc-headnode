/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_crypto = require('crypto');
var mod_fs = require('fs');
var mod_path = require('path');

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var lib_common = require('../../lib/common');

var VError = mod_verror.VError;

/*
 * Globals:
 */
var DEBUG = process.env.DEBUG ? true : false;

function
dfop_assert(arg, next)
{
	mod_assert.object(arg, 'arg');
	mod_assert.object(arg.dfop, 'arg.dfop');
	mod_assert.object(arg.bar, 'arg.bar');
	mod_assert.func(next, 'next');

	return (arg.dfop);
}

function
dfop_check_file(arg, next)
{
	var dfop = dfop_assert(arg, next);

	if (dfop.dfop_retry) {
		next();
		return;
	}

	mod_fs.lstat(dfop.dfop_local_file, function (err, st) {
		if (err) {
			if (err.code === 'ENOENT') {
				if (DEBUG) {
					arg.bar.log('"%s" does not exist',
					    mod_path.basename(
					    dfop.dfop_local_file));
				}
				dfop.dfop_download = true;
				next();
				return;
			}

			next(err);
			return;
		}

		if (!st.isFile()) {
			next(new VError('"%s" is not a regular file',
			    dfop.dfop_local_file));
			return;
		}

		if (st.size !== dfop.dfop_expected_size) {
			if (DEBUG) {
				arg.bar.log(
				    '"%s" size %d, expected %d; unlinking',
				    mod_path.basename(dfop.dfop_local_file),
				    st.size, dfop.dfop_expected_size);
			}
			mod_fs.unlinkSync(dfop.dfop_local_file);
			dfop.dfop_download = true;
			next();
			return;
		}

		next();
	});
}

function
dfop_check_file_checksum(arg, next)
{
	var dfop = dfop_assert(arg, next);

	mod_assert.object(dfop, 'dfop');
	mod_assert.string(dfop.dfop_hash_type, 'hash_type');
	mod_assert.string(dfop.dfop_hash, 'hash');

	if (dfop.dfop_retry || dfop.dfop_download) {
		next();
		return;
	}

	var summer = mod_crypto.createHash(dfop.dfop_hash_type);

	var fstr = mod_fs.createReadStream(dfop.dfop_local_file);
	/*
	 * XXX STREAM ERROR HANDLING
	 */
	fstr.on('readable', function () {
		for (;;) {
			var data = fstr.read(8192);

			if (!data) {
				return;
			}

			summer.update(data);
		}
	});
	fstr.on('end', function () {
		var local_hash = summer.digest('hex');

		if (local_hash === dfop.dfop_hash) {
			dfop.dfop_retry = false;
			dfop.dfop_download = false;
			next();
			return;
		}

		arg.bar.log('"%s" hash = %s, expected %s; unlinking',
		    mod_path.basename(dfop.dfop_local_file),
		    local_hash,
		    dfop.dfop_hash);
		mod_fs.unlinkSync(dfop.dfop_local_file);
		dfop.dfop_download = true;
		next();
	});
}

function
dfop_download_file_http(arg, next)
{
	var dfop = dfop_assert(arg, next);

	if (dfop.dfop_retry || !dfop.dfop_download) {
		next();
		return;
	}

	arg.bar.log('download: %s', mod_path.basename(dfop.dfop_local_file));
	arg.bar.add(dfop.dfop_bit.bit_name, dfop.dfop_expected_size);

	var start = Date.now();
	lib_common.get_via_http(dfop.dfop_url, function (err, res) {
		if (err) {
			next(err);
			return;
		}

		var fstr = mod_fs.createWriteStream(dfop.dfop_local_file, {
			flags: 'wx',
			mode: 0644
		});
		res.pipe(fstr);
		/*
		 * XXX STREAM ERROR HANDLING
		 */
		res.on('data', function (d) {
			arg.bar.advance(dfop.dfop_bit.bit_name, d.length);
		});
		fstr.on('finish', function () {
			var end = Date.now();
			if (DEBUG) {
				arg.bar.log('"%s" downloaded in %d seconds',
				    dfop.dfop_bit.bit_name,
				    (end - start) / 1000);
			}
			dfop.dfop_retry = true;
			dfop.dfop_download = false;
			next();
		});
	});
}

function
dfop_download_file_manta(arg, next)
{
	var dfop = dfop_assert(arg, next);

	if (dfop.dfop_retry || !dfop.dfop_download) {
		next();
		return;
	}

	arg.bar.log('download: %s', mod_path.basename(dfop.dfop_local_file));
	arg.bar.add(dfop.dfop_bit.bit_name, dfop.dfop_expected_size);

	var mstr = arg.manta.createReadStream(dfop.dfop_manta_file);
	var fstr = mod_fs.createWriteStream(dfop.dfop_local_file, {
		flags: 'wx',
		mode: 0644
	});

	/*
	 * XXX STREAM ERROR HANDLING
	 */

	var start = Date.now();
	mstr.pipe(fstr);
	mstr.on('data', function (d) {
		arg.bar.advance(dfop.dfop_bit.bit_name, d.length);
	});
	fstr.on('finish', function () {
		var end = Date.now();
		if (DEBUG) {
			arg.bar.log('"%s" downloaded in %d seconds',
			    dfop.dfop_bit.bit_name, (end - start) / 1000);
		}
		dfop.dfop_retry = true;
		dfop.dfop_download = false;
		next();
	});
}

/*
 * This function works to ensure that a copy of the selected build artifact
 * exists in the cache directory.  If the artifact exists already, its
 * MD5 sum will be verified.  If the MD5 checksum does not match, the file
 * will be deleted and re-downloaded.  Interrupted downloads will be retried
 * several times.
 */
function
work_download_file(wa, next)
{
	mod_assert.object(wa, 'wa');
	mod_assert.object(wa.wa_bit, 'wa.wa_bit');
	mod_assert.object(wa.wa_manta, 'wa.wa_manta');
	mod_assert.object(wa.wa_bar, 'wa.wa_bar');

	var bit = wa.wa_bit;

	mod_assert.string(bit.bit_hash_type, 'bit_hash_type');
	mod_assert.string(bit.bit_hash, 'bit_hash');

	var dfop = {
		dfop_tries: 0,
		dfop_bit: bit,
		dfop_retry: false,
		dfop_download: false,
		dfop_expected_size: bit.bit_size,
		dfop_local_file: bit.bit_local_file,
		dfop_hash: bit.bit_hash,
		dfop_hash_type: bit.bit_hash_type
	};

	var funcs;

	switch (bit.bit_type) {
	case 'manta':
		mod_assert.number(dfop.dfop_expected_size,
		    'dfop_expected_size');
		mod_assert.string(bit.bit_manta_file, 'bit_manta_file');

		dfop.dfop_manta_file = bit.bit_manta_file;
		dfop.dfop_local_file = lib_common.cache_path(mod_path.basename(
		    bit.bit_manta_file));

		funcs = [
			dfop_check_file,
			dfop_check_file_checksum,
			dfop_download_file_manta
		];
		break;

	case 'http':
		mod_assert.number(dfop.dfop_expected_size,
		    'dfop_expected_size');
		mod_assert.string(bit.bit_url, 'bit_url');

		dfop.dfop_url = bit.bit_url;

		funcs = [
			dfop_check_file,
			dfop_check_file_checksum,
			dfop_download_file_http
		];
		break;

	default:
		next(new VError('invalid bit type "%s"', bit.bit_type));
		return;
	}

	var do_try = function () {
		mod_vasync.pipeline({
			funcs: funcs,
			arg: {
				dfop: dfop,
				manta: wa.wa_manta,
				bar: wa.wa_bar
			}
		}, function (err) {
			if (err) {
				next(err);
				return;
			}

			if (dfop.dfop_retry) {
				dfop.dfop_tries++;
				if (DEBUG) {
					wa.wa_bar.log('retrying "%s" time %d',
					    mod_path.basename(
					    dfop.dfop_local_file),
					    dfop.dfop_tries);
				}
				dfop.dfop_retry = false;
				setTimeout(do_try, 1000);
				return;
			}

			bit.bit_local_file = dfop.dfop_local_file;
			next();
		});
	};

	setImmediate(do_try);
}

module.exports = work_download_file;
