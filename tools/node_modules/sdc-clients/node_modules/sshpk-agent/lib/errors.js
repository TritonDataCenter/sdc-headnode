// Copyright 2015 Joyent, Inc.

var assert = require('assert-plus');
var util = require('util');

function AgentProtocolError(frame, msg) {
	if (Error.captureStackTrace)
		Error.captureStackTrace(this, AgentProtocolError);
	this.name = 'AgentProtocolError';
	this.frame = frame;
	this.message = 'Data received from SSH agent could not be decoded: ' +
	    msg;
}
util.inherits(AgentProtocolError, Error);

module.exports = {
	AgentProtocolError: AgentProtocolError
};
