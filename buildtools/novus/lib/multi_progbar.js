/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_fs = require('fs');

var mod_assert = require('assert-plus');
var mod_progbar = require('progbar');
var mod_extsprintf = require('extsprintf');


function
MultiProgressBar(options)
{
	var self = this;

	mod_assert.object(options, 'options');
	mod_assert.bool(options.progbar, 'options.progbar');

	self.mpb_files = {};
	self.mpb_pb = null;

	if (!options.progbar) {
		return;
	}

	/*
	 * Attempt to open the controlling TTY via "/dev/tty".  If there is no
	 * controlling terminal, this will fail -- generally with ENXIO.  In
	 * the event of failure, MultiProgressBar will continue to provide the
	 * log() method, but all other methods will essentially be reduced to
	 * stubs.  This behaviour is useful for builds that may run under
	 * automation; e.g., Jenkins.
	 */
	var fd = -1;
	try {
		fd = mod_fs.openSync('/dev/tty', 'r+');
		mod_assert.ok(fd > 0, 'fd > 0');
	} catch (ex) {
		return;
	}

	/*
	 * If we were able to open the controlling TTY, we _must_ close the
	 * file descriptor.  Catching and discarding this error may lead to an
	 * fd leak.
	 */
	mod_fs.closeSync(fd);

	self.mpb_pb = new mod_progbar.ProgressBar({
		filename: '...',
		size: 1,
		bytes: true,
		devtty: true
	});
}

MultiProgressBar.prototype.total_size = function
total_size()
{
	var self = this;

	if (self.mpb_pb === null) {
		return (0);
	}

	var keys = Object.keys(self.mpb_files);
	var incomplete = 0;
	var total = 1;
	for (var i = 0; i < keys.length; i++) {
		var f = self.mpb_files[keys[i]];

		total += f.file_size;

		if (f.file_done < f.file_size) {
			incomplete++;
		}
	}

	self.mpb_pb.pb_filename = 'downloading ' + incomplete + ' files';

	return (total);
};

MultiProgressBar.prototype.log = function
log()
{
	var self = this;

	var str = mod_extsprintf.sprintf.apply(null, arguments);

	if (self.mpb_pb !== null) {
		self.mpb_pb.log(str);
	} else {
		console.error(str);
	}
};

MultiProgressBar.prototype.add = function
add(name, size)
{
	var self = this;

	if (self.mpb_pb === null) {
		return;
	}

	if (self.mpb_files[name]) {
		self.mpb_files[name].file_size = size;
		self.mpb_files[name].file_done = 0;
	} else {
		self.mpb_files[name] = {
			file_name: name,
			file_size: size,
			file_done: 0
		};
	}
	self.mpb_pb.resize(self.total_size());
};

MultiProgressBar.prototype.remove = function
remove(name)
{
	var self = this;

	if (self.mpb_pb === null) {
		return;
	}

	self.mpb_pb.advance(-self.mpb_files[name].file_done);
	delete (self.mpb_files[name]);
};

MultiProgressBar.prototype.advance = function
advance(name, delta)
{
	var self = this;

	if (self.mpb_pb === null) {
		return;
	}

	self.mpb_files[name].file_done += delta;
	self.total_size();
	self.mpb_pb.advance(delta);
};

MultiProgressBar.prototype.end = function
end()
{
	var self = this;

	if (self.mpb_pb === null) {
		return;
	}

	self.mpb_pb.end();
};

module.exports = {
	MultiProgressBar: MultiProgressBar
};
