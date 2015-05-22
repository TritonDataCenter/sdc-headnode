/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_fs = require('fs');
var mod_path = require('path');
var mod_util = require('util');
var mod_events = require('events');

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_verror = require('verror');

var VError = mod_verror.VError;

var lib_common = require('../lib/common');

var LIB_WORK = {};

function
require_lib_work()
{
	var libdir = mod_path.join(__dirname, '..', 'lib', 'work');
	var ents = mod_fs.readdirSync(libdir);

	for (var i = 0; i < ents.length; i++) {
		var ent = ents[i];
		var m = ent.match(/^(.*)\.js$/);

		if (m) {
			mod_assert.ok(!LIB_WORK[m[1]]);

			LIB_WORK[m[1]] = require(mod_path.join(libdir, ent));
		}
	}
}

function
lib_work(name)
{
	var f = LIB_WORK[name];

	mod_assert.func(f, 'work func "' + name + '"');

	return (f);
}

function
WorkQueue(options)
{
	mod_assert.object(options, 'options');
	mod_assert.number(options.concurrency, 'concurrency');
	mod_assert.object(options.progbar, 'progbar');
	mod_assert.object(options.manta, 'manta');

	var self = this;

	mod_events.EventEmitter.call(self);

	self.wq_epoch = null;
	self.wq_failures = [];
	self.wq_active_files = [];
	self.wq_final = {};
	self.wq_bar = options.progbar;
	self.wq_manta = options.manta;

	self.wq_ended = false;

	self.wq_q = mod_vasync.queuev({
		worker: function (bit, next) {
			self._workfunc(bit, next);
		},
		concurrency: options.concurrency
	});

	self.wq_q.on('end', function () {
		self._on_end();
	});
}
mod_util.inherits(WorkQueue, mod_events.EventEmitter);

WorkQueue.prototype.push = function
push()
{
	var self = this;

	if (self.wq_epoch === null) {
		self.wq_epoch = process.hrtime();
	}

	self.wq_q.push.apply(self.wq_q, arguments);
};

WorkQueue.prototype.close = function
close()
{
	var self = this;

	if (self.wq_epoch === null) {
		self.wq_epoch = process.hrtime();
	}

	setImmediate(function () {
		self.wq_q.close.apply(self.wq_q, arguments);
	});
};

WorkQueue.prototype._workfunc = function
_workfunc(bit, next)
{
	mod_assert.object(bit, 'bit');
	mod_assert.string(bit.bit_type, 'bit.bit_type');
	mod_assert.string(bit.bit_local_file, 'bit.bit_local_file');
	mod_assert.func(next, 'next');

	var self = this;
	var funcs;

	switch (bit.bit_type) {
	case 'manta':
		funcs = [
			'check_manta_md5sum',
			'download_file',
			'make_symlink'
		];
		break;

	case 'json':
		funcs = [
			'write_json_to_file',
			'make_symlink'
		];
		break;

	case 'http':
		funcs = [
			'download_file',
			'make_symlink'
		];
		break;

	default:
		self.wq_failures.push({
			failure_bit: bit,
			failure_err: new VError('invalid bit ' +
			    'type "%s"', bit.bit_type)
		});
		next();
		return;
	}

	var start = process.hrtime();
	mod_vasync.pipeline({
		funcs: funcs.map(lib_work),
		arg: {
			wa_bit: bit,
			wa_manta: self.wq_manta,
			wa_bar: self.wq_bar
		}
	}, function (err) {
		if (err) {
			self.wq_bar.log('ERROR: bit "%s" failed: %s',
			    bit.bit_name, err.message);
			self.wq_failures.push({
				failure_bit: bit,
				failure_err: err
			});
			next(err);
			return;
		}

		self.wq_bar.log('ok:       %s (%d ms)', bit.bit_name,
		    lib_common.delta_ms(start));

		self.wq_final[bit.bit_name] = bit;
		self.wq_active_files.push(mod_path.basename(
		    bit.bit_local_file));

		next();
	});
};

WorkQueue.prototype._on_end = function
_on_end()
{
	var self = this;

	mod_assert.ok(!self.wq_ended, 'workqueue ended twice');
	self.wq_ended = true;

	self.wq_bar.log('download complete (%d ms)',
	    lib_common.delta_ms(self.wq_epoch));
	self.wq_bar.end();

	setImmediate(function () {
		self.emit('end');
	});
};

require_lib_work();

module.exports = {
	WorkQueue: WorkQueue
};
