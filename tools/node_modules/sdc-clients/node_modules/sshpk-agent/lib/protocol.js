// Copyright 2015 Joyent, Inc.

var assert = require('assert-plus');
var util = require('util');
var sshpk = require('sshpk');
var SSHBuffer = require('./ssh-buffer');
var errs = require('./errors');
var AgentProtocolError = errs.AgentProtocolError;

function readClientFrame(buf) {
	var id = buf.readUInt8();
	var obj = {};
	switch (id) {
	case 11:
		obj.type = 'request-identities';
		break;
	case 13:
		obj.type = 'sign-request';
		obj.publicKey = buf.readBuffer();
		obj.data = buf.readBuffer();
		obj.flags = [];

		var flagint = buf.readUInt();
		if ((flagint & 0x01) != 0)
			obj.flags.push('old-signature');
		if ((flagint & 0x02) != 0)
			obj.flags.push('rsa-sha2-256');
		if ((flagint & 0x04) != 0)
			obj.flags.push('rsa-sha2-512');
		break;
	case 17:
		obj.type = 'add-identity';
		obj.privateKey = buf.readPrivateKeyBuf();
		obj.comment = buf.readString();
		break;
	case 18:
		obj.type = 'remove-identity';
		obj.publicKey = buf.readBuffer();
		break;
	case 19:
		obj.type = 'remove-all-identities';
		break;
	case 22:
		obj.type = 'lock';
		obj.password = buf.readString();
		break;
	case 23:
		obj.type = 'unlock';
		obj.password = buf.readString();
		break;
	case 25:
		obj.type = 'add-identity-constrained';
		obj.privateKey = buf.readPrivateKeyBuf();
		obj.comment = buf.readString();
		obj.constraints = [];
		while (!buf.atEnd()) {
			var consType = buf.readUInt8();
			var cons = {};
			switch (consType) {
			case 1:
				cons.type = 'lifetime';
				cons.seconds = buf.readUInt();
				break;
			case 2:
				cons.type = 'confirm';
				break;
			default:
				throw (new AgentProtocolError(util.format(
				    'Unsupported key constraint type: 0x%02x',
				    consType)));
			}
			obj.constraints.push(cons);
		}
		break;
	case 27:
		obj.type = 'extension';
		obj.extension = buf.readString();
		obj.data = buf.readBuffer();
		break;
	default:
		throw (new AgentProtocolError(util.format(
		    'Unsupported message type ID: 0x%02x', id)));
	}
	if (!buf.atEnd()) {
		throw (new AgentProtocolError(util.format(
		    'Message of type "%s" was too long (%d bytes unused)',
		    obj.type, buf.remainder().length)));
	}
	return (obj);
}

function writeClientFrame(obj) {
	var buf = new SSHBuffer({});
	switch (obj.type) {
	case 'request-identities':
		buf.writeUInt8(11);
		break;
	case 'sign-request':
		buf.writeUInt8(13);
		assert.buffer(obj.publicKey, 'publicKey');
		assert.buffer(obj.data, 'data');
		assert.arrayOfString(obj.flags, 'flags');
		buf.writeBuffer(obj.publicKey);
		buf.writeBuffer(obj.data);
		var flagint = 0;
		if (obj.flags.indexOf('old-signature') !== -1)
			flagint |= 0x01;
		if (obj.flags.indexOf('rsa-sha2-256') !== -1)
			flagint |= 0x02;
		if (obj.flags.indexOf('rsa-sha2-512') !== -1)
			flagint |= 0x04;
		buf.writeUInt(flagint);
		break;
	case 'add-identity':
		buf.writeUInt8(17);
		assert.buffer(obj.privateKey, 'privateKey');
		assert.string(obj.comment, 'comment');
		buf.write(obj.privateKey);
		buf.writeString(obj.comment);
		break;
	case 'remove-identity':
		buf.writeUInt8(18);
		assert.buffer(obj.publicKey, 'publicKey');
		buf.writeBuffer(obj.publicKey);
		break;
	case 'remove-all-identities':
		buf.writeUInt8(19);
		break;
	case 'lock':
		buf.writeUInt8(22);
		assert.string(obj.password, 'password');
		buf.writeString(obj.password);
		break;
	case 'unlock':
		buf.writeUInt8(23);
		assert.string(obj.password, 'password');
		buf.writeString(obj.password);
		break;
	case 'add-identity-constrained':
		buf.writeUInt8(25);
		assert.buffer(obj.privateKey, 'privateKey');
		assert.string(obj.comment, 'comment');
		assert.arrayOfObject(obj.constraints, 'constraints');
		buf.write(obj.privateKey);
		buf.writeString(obj.comment);
		obj.constraints.forEach(function (cons) {
			switch (cons.type) {
			case 'lifetime':
				assert.number(cons.seconds, 'cons.seconds');
				buf.writeUInt8(1);
				buf.writeUInt(cons.seconds);
				break;
			case 'confirm':
				buf.writeUInt8(2);
				break;
			default:
				throw (new AgentProtocolError(util.format(
				    'Invalid outgoing key constraint type: ' +
				    '"%s"', cons.type)));
			}
		});
		break;
	case 'extension':
		buf.writeUInt8(27);
		assert.string(obj.extension, 'extension');
		assert.buffer(obj.data, 'data');
		buf.writeString(obj.extension);
		buf.writeBuffer(obj.data);
		break;
	default:
		throw (new AgentProtocolError(util.format('Invalid outgoing ' +
		    'frame type: "%s"', obj.type)));
	}
	return (buf);
}

function readAgentFrame(buf) {
	var id = buf.readUInt8();
	var obj = {};
	switch (id) {
	case 5:
		obj.type = 'failure';
		break;
	case 6:
		obj.type = 'success';
		var rem = buf.remainder();
		/* Extensions can overload the "success" message */
		if (rem.length > 0) {
			obj.remainder = rem;
			return (obj);
		}
		break;
	case 12:
		obj.type = 'identities-answer';
		obj.identities = [];
		var n = buf.readUInt();
		for (var i = 0; i < n; ++i) {
			obj.identities.push({
				key: buf.readBuffer(),
				comment: buf.readString()
			});
		}
		break;
	case 14:
		obj.type = 'sign-response';
		obj.signature = buf.readBuffer();
		break;
	case 28:
		obj.type = 'ext-failure';
		break;
	default:
		throw (new AgentProtocolError(util.format(
		    'Unsupported message type ID: 0x%02x', id)));
	}
	if (!buf.atEnd()) {
		throw (new AgentProtocolError(util.format(
		    'Message of type "%s" was too long (%d bytes unused)',
		    obj.type, buf.remainder().length)));
	}
	return (obj);
}

function writeAgentFrame(obj) {
	var buf = new SSHBuffer({});
	switch (obj.type) {
	case 'failure':
		buf.writeUInt8(5);
		break;
	case 'success':
		buf.writeUInt8(6);
		if (obj.remainder !== undefined) {
			assert.buffer(obj.remainder, 'remainder');
			buf.write(obj.remainder);
		}
		break;
	case 'identities-answer':
		buf.writeUInt8(12);
		assert.optionalArrayOfObject(obj.identities, 'identities');
		if (!obj.identities) {
			buf.writeUInt(0);
		} else {
			buf.writeUInt(obj.identities.length);
			obj.identities.forEach(function (id) {
				assert.buffer(id.key, 'key');
				assert.string(id.comment, 'comment');
				buf.writeBuffer(id.key);
				buf.writeString(id.comment);
			});
		}
		break;
	case 'sign-response':
		buf.writeUInt8(14);
		assert.buffer(obj.signature, 'signature');
		buf.writeBuffer(obj.signature);
		break;
	case 'ext-failure':
		buf.writeUInt8(28);
		break;
	default:
		throw (new AgentProtocolError(util.format('Invalid outgoing ' +
		    'frame type: "%s"', obj.type)));
	}
	return (buf);
}

module.exports = {
	readClientFrame: readClientFrame,
	readAgentFrame: readAgentFrame,
	writeClientFrame: writeClientFrame,
	writeAgentFrame: writeAgentFrame
};
