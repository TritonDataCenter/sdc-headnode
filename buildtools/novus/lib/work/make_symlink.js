/* vim: set ts=8 sts=8 sw=8 noet: */
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2015 Joyent, Inc.
 */

var mod_fs = require('fs');
var mod_path = require('path');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var lib_common = require('../../lib/common');

var VError = mod_verror.VError;

function
work_make_symlink(wa, next)
{
	mod_assert.object(wa, 'wa');
	mod_assert.object(wa.wa_bit, 'wa.wa_bit');
	mod_assert.func(next, 'next');

	var bit = wa.wa_bit;

	mod_assert.string(bit.bit_local_file, 'bit_local_file');
	mod_assert.optionalString(bit.bit_make_symlink, 'bit_make_symlink');

	if (!bit.bit_make_symlink) {
		next();
		return;
	}

	var link_path = lib_common.cache_path(bit.bit_make_symlink);

	try {
		mod_fs.unlinkSync(link_path);
	} catch (err) {
		if (err.code !== 'ENOENT') {
			next(new VError(err, 'unlink "%s" failed', link_path));
			return;
		}
	}

	mod_fs.symlinkSync(mod_path.basename(bit.bit_local_file),
	    link_path);

	next();
}

module.exports = work_make_symlink;
