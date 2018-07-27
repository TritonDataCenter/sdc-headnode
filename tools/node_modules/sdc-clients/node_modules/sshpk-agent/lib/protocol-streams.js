// Copyright 2015 Joyent, Inc.

var assert = require('assert-plus');
var util = require('util');

var stream = require('stream');
if (process.version.match(/^v0[.]1[0-1][.]/))
	stream = require('readable-stream');

var protocol = require('./protocol');
var errs = require('./errors');
var AgentProtocolError = errs.AgentProtocolError;
var SSHBuffer = require('./ssh-buffer');

function AgentEncodeStream(opts) {
	assert.object(opts, 'options');
	assert.string(opts.role, 'options.role');
	this.role = opts.role.toLowerCase();
	switch (this.role) {
	case 'agent':
		this.convert = protocol.writeAgentFrame;
		break;
	case 'client':
		this.convert = protocol.writeClientFrame;
		break;
	default:
		/* assert below will fail */
		break;
	}
	assert.func(this.convert, 'convert func for role ' + this.role);

	opts.readableObjectMode = false;
	opts.writableObjectMode = true;
	stream.Transform.call(this, opts);
}
util.inherits(AgentEncodeStream, stream.Transform);

AgentEncodeStream.prototype._transform = function (obj, enc, cb) {
	assert.object(obj);

	var buf = new SSHBuffer({});
	try {
		var kbuf = this.convert(obj);
		buf.writeb(kbuf);

		this.push(buf.toBuffer());
	} catch (e) {
		this.emit('error', e);
	}
	cb();
};

AgentEncodeStream.prototype._flush = function (cb) {
	cb();
};


function AgentDecodeStream(opts) {
	assert.object(opts, 'options');
	assert.string(opts.role, 'options.role');
	this.role = opts.role.toLowerCase();
	switch (this.role) {
	case 'agent':
		this.convert = protocol.readClientFrame;
		break;
	case 'client':
		this.convert = protocol.readAgentFrame;
		break;
	default:
		/* assert below will fail */
		break;
	}
	assert.func(this.convert, 'convert func for role ' + this.role);

	opts.readableObjectMode = true;
	opts.writableObjectMode = false;
	stream.Transform.call(this, opts);

	this.frame = new Buffer(0);
}
util.inherits(AgentDecodeStream, stream.Transform);

AgentDecodeStream.prototype._transform = function (chunk, enc, cb) {
	this.frame = Buffer.concat([this.frame, chunk]);

	while (this.frame.length >= 4) {
		var len = this.frame.readUInt32BE(0);

		if (this.frame.length < (len + 4)) {
			/*
			 * Keep it buffered up, see if we get the rest of
			 * it next time around
			 */
			break;

		} else {
			/* We have an entire frame, let's process it */
			var frame = this.frame.slice(4, len + 4);
			this.frame = this.frame.slice(len + 4);
			var buf = new SSHBuffer({ buffer: frame });

			try {
				var obj = this.convert(buf);
				this.push(obj);
			} catch (e) {
				this.emit('error', e);
			}
		}
	}
	cb();
};

AgentDecodeStream.prototype._flush = function (cb) {
	if (this.frame.length > 0) {
		var err = new AgentProtocolError(this.frame,
		    'leftover bytes in buffer not used at flush time');
		this.emit('error', err);
		cb();
		return;
	}
	cb();
};


module.exports = {
	AgentDecodeStream: AgentDecodeStream,
	AgentEncodeStream: AgentEncodeStream
};
