/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_fs = require('fs');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var VError = mod_verror.VError;


function
work_write_json_to_file(wa, next)
{
	mod_assert.object(wa, 'wa');
	mod_assert.object(wa.wa_bit, 'wa.wa_bit');
	mod_assert.func(next, 'next');

	var bit = wa.wa_bit;

	mod_assert.strictEqual(bit.bit_type, 'json');
	mod_assert.string(bit.bit_local_file, 'bit_local_file');
	mod_assert.object(bit.bit_json, 'bit_json');

	var out = JSON.stringify(bit.bit_json);
	try {
		mod_fs.unlinkSync(bit.bit_local_file);
	} catch (ex) {
		if (ex.code !== 'ENOENT') {
			next(new VError(ex, 'could not unlink "%s"',
			    bit.bit_local_file));
			return;
		}
	}

	mod_fs.writeFile(bit.bit_local_file, out, {
		encoding: 'utf8',
		mode: 0644,
		flag: 'wx'
	}, function (err) {
		if (err) {
			next (new VError(err, 'could not write file "%s"',
			    bit.bit_local_file));
			return;
		}

		next();
	});
}

module.exports = work_write_json_to_file;
