/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_fs = require('fs');
var mod_child = require('child_process');

var mod_assert = require('assert-plus');
var mod_verror = require('verror');

var VError = mod_verror.VError;

function
exec_ln(src, dst, next)
{
	mod_child.execFile('/bin/ln', [
		src,
		dst
	], function (err, stdout, stderr) {
		if (err) {
			next(new VError(err, 'failed to execute /bin/ln ' +
			    '"%s" "%s"', src, dst));
			return;
		}

		next();
	});
}

function
work_copy_local_file(wa, next)
{
	mod_assert.object(wa, 'wa');
	mod_assert.object(wa.wa_bit, 'wa.wa_bit');
	mod_assert.object(wa.wa_bar, 'wa.wa_bar');

	var bit = wa.wa_bit;

	mod_assert.string(bit.bit_source_file, 'bit_source_file');
	mod_assert.string(bit.bit_local_file, 'bit_local_file');

	try {
		mod_fs.unlinkSync(bit.bit_local_file);
	} catch (ex) {
		if (ex.code !== 'ENOENT') {
			next(new VError(ex, 'could not unlink "%s"',
			    bit.bit_local_file));
			return;
		}
	}

	exec_ln(bit.bit_source_file, bit.bit_local_file, next);
}

module.exports = work_copy_local_file;
