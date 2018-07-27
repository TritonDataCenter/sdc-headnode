// Copyright 2015 Joyent, Inc.

module.exports = ClientFSM;

var assert = require('assert-plus');
var crypto = require('crypto');
var sshpk = require('sshpk');
var util = require('util');
var EventEmitter = require('events').EventEmitter;
var net = require('net');
var errs = require('./errors');
var VError = require('verror');
var AgentProtocolError = errs.AgentProtocolError;

var protoStreams = require('./protocol-streams');
var AgentEncodeStream = protoStreams.AgentEncodeStream;
var AgentDecodeStream = protoStreams.AgentDecodeStream;

var FSM = require('mooremachine').FSM;

/*
 * The ssh-agent client state machine is actually built from 3 smaller FSMs,
 * in order to stay sane while handling all the different error and timeout
 * paths that are possible.
 *
 * The ClientFSM itself simply manages keeping a connection open, and having
 * it ref'd or unref'd. On node >=0.10 it can idle the connection, so as to
 * not have to re-open it from scratch when another request comes in.
 *
 * The Request FSM manages the lifecycle of an individual request to the agent,
 * while RequestQueue manages the queue of requests and deciding which one
 * should currenty have control of the Client.
 */

function RequestQueue(client) {
	this.rq_client = client;
	this.rq_recent = [];
	this.rq_queue = [];
	this.rq_request = undefined;
	FSM.call(this, 'idle');
}
util.inherits(RequestQueue, FSM);

/*
 * STATE: idle
 * when there is a request on the rq_queue => STATE connect
 */
RequestQueue.prototype.state_idle = function (S) {
	/*
	 * Store the last request, if any, for a while, to make
	 * debugging a little easier.
	 */
	if (this.rq_request)
		this.rq_recent.push(this.rq_request);
	if (this.rq_recent.length > 4)
		this.rq_recent.shift();

	/*
	 * Transitions out of the idle state occur when there is a
	 * request on the rq_queue.
	 */
	if (this.rq_queue.length > 0) {
		S.gotoState('connect');
	} else {
		this.rq_client.unref();
		S.on(this, 'nonEmptyAsserted', function () {
			S.gotoState('connect');
		});
	}
};

/*
 * STATE: connect
 * when the client has connected => STATE req
 */
RequestQueue.prototype.state_connect = function (S) {
	/*
	 * Transition out of the connect state when the client has
	 * been connected successfully.
	 */
	this.rq_client.ref();
	if (this.rq_client.isInState('connected')) {
		S.gotoState('req');
	} else {
		S.on(this.rq_client, 'stateChanged', function (st) {
			if (st === 'connected')
				S.gotoState('req');
		});
		this.rq_client.connect();
	}
};

/*
 * STATE: req
 * when the request reaches 'done' => STATE idle
 */
RequestQueue.prototype.state_req = function (S) {
	assert.ok(this.rq_queue.length > 0);
	this.rq_request = this.rq_queue.shift();

	assert.ok(this.rq_request.isInState('waiting'));

	/* Transition to idle when the request is done. */
	S.on(this.rq_request, 'stateChanged', function (st) {
		if (st === 'done')
			S.gotoState('idle');
	});
	this.rq_request.ready();
};

RequestQueue.prototype.push = function (req) {
	assert.ok(req instanceof Request);
	var ret = this.rq_queue.push(req);
	this.emit('nonEmptyAsserted');
	return (ret);
};


function Request(client, sendFrame, respTypes, timeout, cb) {
	assert.ok(client instanceof ClientFSM);
	this.r_client = client;

	assert.object(sendFrame, 'sendFrame');
	this.r_sendFrame = sendFrame;

	assert.arrayOfString(respTypes, 'respTypes');
	this.r_respTypes = respTypes;

	assert.number(timeout, 'timeout');
	this.r_timeout = timeout;

	this.r_error = undefined;
	this.r_reply = undefined;
	this.r_retries = 3;

	assert.func(cb, 'callback');
	this.r_cb = cb;

	FSM.call(this, 'waiting');
}
util.inherits(Request, FSM);

/*
 * STATE: waiting
 * when ready is asserted => STATE sending
 */
Request.prototype.state_waiting = function (S) {
	/* Wait for the "ready" signal. */
	S.on(this, 'readyAsserted', function () {
		S.gotoState('sending');
	});
};

/*
 * STATE: sending
 * when a timeout occurs => STATE error
 * when an error occurs on the client => STATE error
 * when a frame is received on the client => STATE error or STATE done
 */
Request.prototype.state_sending = function (S) {
	var self = this;
	this.r_error = undefined;
	this.r_reply = undefined;

	/* Transitions out of sending are to either error or done. */

	S.timeout(this.r_timeout, function () {
		self.r_error = new Error('Timeout waiting for ' +
		    'response from SSH agent (' + self.r_timeout +
		    ' ms)');
		self.r_client.disconnect();
		S.gotoState('error');
	});

	S.on(this.r_client, 'error', function (err) {
		self.r_error = err;
		S.gotoState('error');
	});

	S.on(this.r_client, 'frame', function (frame) {
		if (self.r_respTypes.indexOf(frame.type) === -1) {
			self.r_error = new AgentProtocolError(frame,
			    'Frame received from agent out of order. ' +
			    'Got a ' + frame.type + ', expected a ' +
			    self.r_respTypes.join(' or '));
			S.gotoState('error');
			return;
		}
		self.r_reply = frame;
		S.gotoState('done');
	});

	this.r_client.sendFrame(this.r_sendFrame);
};

/*
 * STATE: error
 * when there are retries remaining => STATE sending
 * otherwise => STATE done
 */
Request.prototype.state_error = function (S) {
	if (this.r_retries > 0) {
		--this.r_retries;
		if (this.r_client.isInState('connected')) {
			S.gotoState('sending');
		} else {
			S.on(this.r_client, 'stateChanged', function (st) {
				if (st === 'connected')
					S.gotoState('sending');
			});
			this.r_client.connect();
		}
	} else {
		S.gotoState('done');
	}
};

/*
 * STATE: done
 * terminus
 */
Request.prototype.state_done = function () {
	if (this.r_error === undefined) {
		this.r_cb(null, this.r_reply);
	} else {
		this.r_cb(this.r_error);
	}
};

Request.prototype.ready = function () {
	this.emit('readyAsserted');
};



function ClientFSM(opts) {
	if (opts === undefined)
		opts = {};
	assert.object(opts, 'options');
	var sockPath = opts.socketPath;
	if (sockPath === undefined)
		sockPath = process.env['SSH_AUTH_SOCK'];
	assert.string(sockPath, 'options.socketPath or $SSH_AUTH_SOCK');
	assert.optionalNumber(opts.timeout, 'options.timeout');

	this.c_sockPath = sockPath;
	this.c_timeout = opts.timeout || 2000;
	this.c_socket = undefined;
	this.c_encodeStream = undefined;
	this.c_decodeStream = undefined;
	this.c_connectError = undefined;
	this.c_connectRetries = 3;
	this.c_lastError = undefined;
	this.c_ref = false;

	FSM.call(this, 'disconnected');
	this.c_rq = new RequestQueue(this);
}
util.inherits(ClientFSM, FSM);

/*
 * STATE: disconnected
 * when connect asserted => STATE connecting
 */
ClientFSM.prototype.state_disconnected = function (S) {
	S.on(this, 'connectAsserted', function () {
		S.gotoState('connecting');
	});
};

/*
 * STATE: connecting
 * when socket emits error => STATE connectError
 * when timeout occurs => STATE connectError
 * when socket connects => STATE connected
 */
ClientFSM.prototype.state_connecting = function (S) {
	var self = this;

	this.c_socket = net.connect(this.c_sockPath);

	S.timeout(this.c_timeout, function () {
		var err = new VError('connect() timed out (%d ms)',
		    self.c_timeout);
		self.c_connectError = new VError(err,
		    'Error while connecting to socket: %s', self.c_sockPath);
		S.gotoState('connectError');
	});

	S.on(this.c_socket, 'error', function (err) {
		self.c_connectError = new VError(err,
		    'Error while connecting to socket: %s', self.c_sockPath);
		S.gotoState('connectError');
	});

	S.on(this.c_socket, 'connect', function () {
		S.gotoState('connected');
	});
};

/*
 * STATE: connectError
 * when there are retries left => STATE connecting
 * otherwise => STATE disconnected
 */
ClientFSM.prototype.state_connectError = function (S) {
	var self = this;
	this.c_socket.destroy();
	this.c_socket = undefined;
	if (this.c_connectRetries > 0) {
		--this.c_connectRetries;
		S.gotoState('connecting');
	} else {
		this.c_wantConnect = false;
		setImmediate(function () {
			self.emit('error', self.c_connectError);
		});
		S.gotoState('disconnected');
	}
};

/*
 * STATE: connected
 * when socket or stream errors occur => STATE disconnecting
 * when disconnect asserted => STATE disconnecting
 * when socket closes => STATE disconnecting
 * if c_red asserted always => SUBSTATE busy
 * else always => SUBSTATE idle
 */
ClientFSM.prototype.state_connected = function (S) {
	var self = this;

	this.c_connectRetries = 3;
	this.c_encodeStream = new AgentEncodeStream({role: 'client'});
	this.c_decodeStream = new AgentDecodeStream({role: 'client'});
	this.c_socket.pipe(this.c_decodeStream);
	this.c_encodeStream.pipe(this.c_socket);

	var errHandler = function (err) {
		self.c_lastError = new VError(err, 'Error emitted while ' +
		    'connected to socket: %s', self.c_sockPath);
		self.emit('error', err);
		S.gotoState('disconnecting');
	};

	S.on(this.c_socket, 'error', errHandler);
	S.on(this.c_decodeStream, 'error', errHandler);
	S.on(this.c_encodeStream, 'error', errHandler);

	S.on(this.c_socket, 'close', function () {
		if (self.c_ref) {
			errHandler(new Error('Unexpectedly lost ' +
			    'connection to SSH agent'));
		} else {
			S.gotoState('disconnecting');
		}
	});

	S.on(this.c_decodeStream, 'readable', function () {
		var frame;
		while (self.c_decodeStream &&
		    (frame = self.c_decodeStream.read())) {
			if (self.listeners('frame').length < 1) {
				errHandler(new Error('Unexpected ' +
				    'frame received from SSH agent: ' +
				    frame.type));
				return;
			}
			self.emit('frame', frame);
		}
	});

	S.on(this, 'disconnectAsserted', function () {
		S.gotoState('disconnecting');
	});

	if (this.c_ref)
		S.gotoState('connected.busy');
	else
		S.gotoState('connected.idle');
};

/*
 * STATE: connected.busy
 * when unref asserted => SUBSTATE idle
 */
ClientFSM.prototype.state_connected.busy = function (S) {
	if (this.c_socket.ref)
		this.c_socket.ref();
	S.on(this, 'unrefAsserted', function () {
		S.gotoState('connected.idle');
	});
};

/*
 * STATE: connected.idle
 * if on node <= 0.8 => STATE disconnecting
 * when ref asserted => SUBSTATE busy
 */
ClientFSM.prototype.state_connected.idle = function (S) {
	if (this.c_socket.unref) {
		this.c_socket.unref();
		S.on(this, 'refAsserted', function () {
			S.gotoState('connected.busy');
		});
	} else {
		S.gotoState('disconnecting');
	}
};

/*
 * STATE: disconnecting
 * always => STATE disconnected
 */
ClientFSM.prototype.state_disconnecting = function (S) {
	this.c_socket.destroy();
	this.c_socket = undefined;

	this.c_encodeStream = undefined;
	this.c_decodeStream = undefined;

	S.gotoState('disconnected');
};

ClientFSM.prototype.ref = function () {
	this.c_ref = true;
	this.emit('refAsserted');
};

ClientFSM.prototype.unref = function () {
	this.c_ref = false;
	this.emit('unrefAsserted');
};

ClientFSM.prototype.disconnect = function () {
	this.emit('disconnectAsserted');
};

ClientFSM.prototype.connect = function (cb) {
	assert.optionalFunc(cb, 'callback');
	assert.ok(this.isInState('disconnected'),
	    'client must be disconnected');
	var self = this;
	if (cb) {
		function onStateChanged(st) {
			if (st === 'connected') {
				self.removeListener('stateChanged',
				    onStateChanged);
				cb();
			}
		}
		this.on('stateChanged', onStateChanged);
	}
	this.emit('connectAsserted');
};

ClientFSM.prototype.sendFrame = function (frame) {
	assert.ok(this.c_encodeStream);
	this.c_encodeStream.write(frame);
};

ClientFSM.prototype.doRequest = function (frame, resps, timeout, cb) {
	var req = new Request(this, frame, resps,
	    timeout || this.c_timeout, cb);
	this.c_rq.push(req);
};
