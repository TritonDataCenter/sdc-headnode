// Copyright 2015 Joyent, Inc.

var Client = require('./client');
var errs = require('./errors');

module.exports = {
	Client: Client,

	AgentProtocolError: errs.AgentProtocolError
};
