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

/*
 * Manta maintains an MD5 checksum for each uploaded object that we can query
 * without downloading the file.  We check that this MD5 checksum matches the
 * expected value from the manifest before downloading.
 */
function
work_check_manta_md5sum(wa, next)
{
	mod_assert.object(wa, 'wa');
	mod_assert.object(wa.wa_bit, 'wa.wa_bit');
	mod_assert.object(wa.wa_bit, 'wa.wa_manta');
	mod_assert.func(next, 'next');

	var bit = wa.wa_bit;

	mod_assert.string(bit.bit_hash, 'bit_hash');
	mod_assert.strictEqual(bit.bit_hash_type, 'md5');
	mod_assert.string(bit.bit_manta_file, 'bit_manta_file');

	wa.wa_manta.info(bit.bit_manta_file, function (err, info) {
		if (err) {
			next(new VError(err, 'could not get info about "%s"',
			    bit.bit_manta_file));
			return;
		}

		mod_assert.string(info.md5, 'info.md5');
		mod_assert.number(info.size, 'info.size');

		/*
		 * Manta MD5 sums are BASE64-encoded.  We must convert it
		 * to a hex string for comparison with the manifest value.
		 */
		bit.bit_manta_md5sum = new Buffer(
		    info.md5, 'base64').toString('hex');
		bit.bit_size = info.size;

		if (bit.bit_hash === bit.bit_manta_md5sum) {
			next();
			return;
		}

		next(new VError('Manta MD5 "%s" did not match manifest ' +
		    'MD5 "%s"', bit.bit_manta_md5sum, bit.bit_hash));
	});
}

module.exports = work_check_manta_md5sum;
