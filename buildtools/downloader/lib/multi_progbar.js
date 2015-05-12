/* vim: set ts=8 sts=8 sw=8 noet: */

var mod_progbar = require('progbar');
var mod_extsprintf = require('extsprintf');


function
MultiProgressBar()
{
	var self = this;

	self.mpb_pb = new mod_progbar.ProgressBar({
		filename: '...',
		size: 1,
		bytes: true,
		devtty: true
	});
	self.mpb_files = {};
}

MultiProgressBar.prototype.total_size = function
total_size()
{
	var self = this;

	var keys = Object.keys(self.mpb_files);
	var total = 1;
	for (var i = 0; i < keys.length; i++) {
		var f = self.mpb_files[keys[i]];

		total += f.file_size;
	}

	self.mpb_pb.pb_filename = 'downloading ' + keys.length + ' files...';

	return (total);
};

MultiProgressBar.prototype.log = function
log()
{
	var self = this;

	var str = mod_extsprintf.sprintf.apply(null, arguments);

	self.mpb_pb.log(str);
};

MultiProgressBar.prototype.add = function
add(name, size)
{
	var self = this;

	if (self.mpb_files[name]) {
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

	self.mpb_pb.advance(-self.mpb_files[name].file_done);
	delete (self.mpb_files[name]);
};

MultiProgressBar.prototype.advance = function
advance(name, delta)
{
	var self = this;

	self.mpb_files[name].file_done += delta;
	self.mpb_pb.advance(delta);
};

MultiProgressBar.prototype.end = function
end()
{
	var self = this;

	self.mpb_pb.end();
};

module.exports = {
	MultiProgressBar: MultiProgressBar
};
