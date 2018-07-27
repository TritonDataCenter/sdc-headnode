// Copyright 2015 Joyent, Inc.

var assert = require('assert-plus');
var sshpk = require('sshpk');
var sshpkUtils = require('sshpk/lib/utils');
var util = require('util');
var errors = require('./errors');
var SSHBuffer = require('./ssh-buffer');
var AgentProtocolError = errors.AgentProtocolError;

var ClientFSM = require('./client-fsm');

function Client(opts) {
	ClientFSM.call(this, opts);
}
util.inherits(Client, ClientFSM);

Client.prototype.listKeys = function (opts, cb) {
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {type: 'request-identities'};
	var resps = ['identities-answer', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}

		if (resp.type === 'failure') {
			cb(new Error('SSH agent returned "failure" to ' +
			    '"request-identities". (Agent locked, or ' +
			    'device not present?)'));
			return;
		}
		assert.strictEqual(resp.type, 'identities-answer');

		var keys = [];
		for (var i = 0; i < resp.identities.length; ++i) {
			var id = resp.identities[i];
			var sshbuf = new SSHBuffer({ buffer: id.key });
			var type = sshbuf.readString();
			if (type.indexOf('-cert-') !== -1) {
				/* Just skip over any certificates */
				continue;
			}
			try {
				var key = sshpk.parseKey(id.key, 'rfc4253');
				key.comment = id.comment;
				keys.push(key);
			} catch (e) {
				var err2 = new AgentProtocolError(resp,
				    'Failed to parse key in ssh-agent ' +
				    'response: ' + e.name + ': ' + e.message);
				cb(err2);
				return;
			}
		}

		cb(null, keys);
	});
};

Client.prototype.listCertificates = function (opts, cb) {
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {type: 'request-identities'};
	var resps = ['identities-answer', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}

		if (resp.type === 'failure') {
			cb(new Error('SSH agent returned "failure" to ' +
			    '"request-identities". (Agent locked, or ' +
			    'device not present?)'));
			return;
		}
		assert.strictEqual(resp.type, 'identities-answer');

		var certs = [];
		for (var i = 0; i < resp.identities.length; ++i) {
			var id = resp.identities[i];
			var sshbuf = new SSHBuffer({ buffer: id.key });
			var type = sshbuf.readString();
			if (type.indexOf('-cert-') === -1) {
				/* Just skip over any plain keys */
				continue;
			}
			try {
				var cert = sshpk.Certificate.formats.openssh.
				    fromBuffer(id.key);
				cert.comment = id.comment;
				certs.push(cert);
			} catch (e) {
				var err2 = new AgentProtocolError(resp,
				    'Failed to parse cert in ssh-agent ' +
				    'response: ' + e.name + ': ' + e.message);
				cb(err2);
				return;
			}
		}

		cb(null, certs);
	});
};

Client.prototype.sign = function (key, data, opts, cb) {
	assert.object(key, 'key');
	if (typeof (data) === 'string')
		data = new Buffer(data);
	assert.buffer(data, 'data');
	assert.ok(sshpk.Key.isKey(key, [1, 3]), 'key must be an sshpk.Key');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	assert.func(cb, 'callback');
	var timeout = opts.timeout || this.timeout;

	var frame = {
		type: 'sign-request',
		publicKey: key.toBuffer('rfc4253'),
		data: data,
		flags: ['rsa-sha2-256']
	};
	var resps = ['failure', 'sign-response'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}

		if (resp.type === 'failure') {
			cb(new Error('SSH agent returned "failure" ' +
			    'code in response to "sign-request" ' +
			    '(key not found, user refused confirmation, ' +
			    'or other failure)'));
			return;
		}
		assert.strictEqual(resp.type, 'sign-response');

		try {
			var sig = sshpk.parseSignature(resp.signature,
			    key.type, 'ssh');

			/* Emulate the openssh hash algorithm choice */
			if (typeof (sig.hashAlgorithm) !== 'string') {
				switch (key.type) {
				case 'rsa':
				case 'dsa':
					sig.hashAlgorithm = 'sha1';
					break;
				case 'ecdsa':
					if (key.size <= 256)
						sig.hashAlgorithm = 'sha256';
					else if (key.size <= 384)
						sig.hashAlgorithm = 'sha384';
					else
						sig.hashAlgorithm = 'sha512';
					break;
				case 'ed25519':
					sig.hashAlgorithm = 'sha512';
					break;
				default:
					throw (new Error('Failed to ' +
					    'determine hash algorithm in use ' +
					    'with key type ' + key.type));
				}
			}
		} catch (e) {
			var err2 = new AgentProtocolError(resp,
			    'Failed to parse signature in ssh-agent ' +
			    'response: ' + e.name + ': ' + e.message);
			cb(err2);
			return;
		}

		cb(null, sig);
	});
};

var SIGFORMATS = {
	'x509': require('sshpk/lib/formats/x509'),
	'openssh': require('sshpk/lib/formats/openssh-cert')
};

Client.prototype.signCertificate = function (cert, key, cb) {
	var signer = this.sign.bind(this, key);
	var hashAlgo;
	var done = 0;
	var errs = [];
	var fmts = Object.keys(SIGFORMATS);

	/*
	 * When we ask the agent to sign the certificate, we're going to send
	 * the RSA-SHA256 flag. The agent may not support this flag, however,
	 * and so could either give us a SHA1 or a SHA256 signature. We can't
	 * know until after we ask it to sign something.
	 *
	 * Since we have to know which of these is being used in advance for
	 * x509 certificates (the algorithm in use is part of the signed data),
	 * ask the agent to sign a dummy value ('test') so we can see whether
	 * it's going to use SHA1 or SHA256.
	 */
	this.sign(key, new Buffer('test', 'ascii'), {}, function (err, sig) {
		if (err) {
			cb(err);
			return;
		}
		hashAlgo = sig.hashAlgorithm;
		doSignatures();
	});

	function doSignatures() {
		fmts.forEach(function (fmt) {
			cert.signatures[fmt] = {};
			cert.signatures[fmt].algo = key.type + '-' + hashAlgo;
			SIGFORMATS[fmt].signAsync(cert, signer, function (err) {
				if (err) {
					errs.push(err);
					delete (cert.signatures[fmt]);
				}
				if (++done >= fmts.length) {
					finish();
				}
			});
		});
	}

	function finish() {
		if (errs.length >= done) {
			cb(new Error('Failed to sign the certificate for any ' +
			    'available certificate formats'));
			return;
		}
		cb();
	}
};

function arrayOrArrayOfOne(thingOrThings) {
	if (Array.isArray(thingOrThings))
		return (thingOrThings);
	else
		return ([thingOrThings]);
}

Client.prototype.createSelfSignedCertificate =
    function (subjectOrSubjects, key, options, cb) {
	var subjects = arrayOrArrayOfOne(subjectOrSubjects);
	if (options === undefined)
		options = {};
	options.ca = true;
	this.createCertificate(subjects, key, subjects[0], key, options, cb);
};

Client.prototype.createCertificate =
    function (subjectOrSubjects, key, issuer, issuerKey, options, cb) {
	var subjects = arrayOrArrayOfOne(subjectOrSubjects);

	assert.arrayOfObject(subjects);
	subjects.forEach(function (subject) {
		sshpkUtils.assertCompatible(subject, sshpk.Identity, [1, 0],
		    'subject');
	});

	sshpkUtils.assertCompatible(key, sshpk.Key, [1, 0], 'key');
	if (sshpk.PrivateKey.isPrivateKey(key))
		key = key.toPublic();
	sshpkUtils.assertCompatible(issuer, sshpk.Identity, [1, 0], 'issuer');
	sshpkUtils.assertCompatible(issuerKey, sshpk.Key, [1, 0], 'issuer key');

	assert.optionalObject(options, 'options');
	if (options === undefined)
		options = {};
	assert.optionalObject(options.validFrom, 'options.validFrom');
	assert.optionalObject(options.validUntil, 'options.validUntil');
	var validFrom = options.validFrom;
	var validUntil = options.validUntil;
	if (validFrom === undefined)
		validFrom = new Date();
	if (validUntil === undefined) {
		assert.optionalNumber(options.lifetime, 'options.lifetime');
		var lifetime = options.lifetime;
		if (lifetime === undefined)
			lifetime = 10*365*24*3600;
		validUntil = new Date();
		validUntil.setTime(validUntil.getTime() + lifetime*1000);
	}
	assert.optionalBuffer(options.serial, 'options.serial');
	var serial = options.serial;
	if (serial === undefined)
		serial = new Buffer('0000000000000001', 'hex');

	var purposes = options.purposes;
	if (purposes === undefined)
		purposes = [];

	if (purposes.indexOf('signature') === -1)
		purposes.push('signature');

	if (options.ca === true) {
		if (purposes.indexOf('ca') === -1)
			purposes.push('ca');
		if (purposes.indexOf('crl') === -1)
			purposes.push('crl');
	}

	var hostSubjects = subjects.filter(function (subject) {
		return (subject.type === 'host');
	});
	var userSubjects = subjects.filter(function (subject) {
		return (subject.type === 'user');
	});
	if (hostSubjects.length > 0) {
		if (purposes.indexOf('serverAuth') === -1)
			purposes.push('serverAuth');
	}
	if (userSubjects.length > 0) {
		if (purposes.indexOf('clientAuth') === -1)
			purposes.push('clientAuth');
	}
	if (userSubjects.length > 0 || hostSubjects.length > 0) {
		if (purposes.indexOf('keyAgreement') === -1)
			purposes.push('keyAgreement');
		if (key.type === 'rsa' &&
		    purposes.indexOf('encryption') === -1)
			purposes.push('encryption');
	}

	var cert = new sshpk.Certificate({
		subjects: subjects,
		issuer: issuer,
		subjectKey: key,
		issuerKey: issuerKey,
		signatures: {},
		serial: serial,
		validFrom: validFrom,
		validUntil: validUntil,
		purposes: purposes
	});

	this.signCertificate(cert, issuerKey, function (err) {
		if (err) {
			cb(err);
			return;
		}
		cb(null, cert);
	});
};

/*
 * The agent protocol encodes the private keys that go with a given certificate
 * as simply the private-only parts of the key appended to the certificate
 * blob. We can't really expect sshpk itself to support this encoding (as
 * it's not even documented, let alone used anywhere else).
 */
function certToBuffer(cert, k) {
	var buf = sshpk.Certificate.formats.openssh.toBuffer(cert);
	var sshbuf = new SSHBuffer({ buffer: buf });
	var type = sshbuf.readString();

	sshbuf = new SSHBuffer({});
	sshbuf.writeString(type);
	sshbuf.writeBuffer(buf);
	switch (k.type) {
	case 'dsa':
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.x.data));
		break;
	case 'ecdsa':
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.d.data));
		break;
	case 'rsa':
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.d.data));
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.iqmp.data));
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.p.data));
		sshbuf.writeBuffer(sshpkUtils.mpNormalize(k.part.q.data));
		break;
	case 'ed25519':
		/*
		 * For some reason the public key gets encoded again for
		 * ed25519 certs. The mysteries will never cease.
		 */
		sshbuf.writeBuffer(k.part.A.data);
		var edk = Buffer.concat([k.part.A.data, k.part.k.data]);
		sshbuf.writeBuffer(edk);
		break;
	default:
		throw (new Error('Key type ' + k.type + ' not supported'));
	}
	return (sshbuf.toBuffer());
}

Client.prototype.addCertificate = function (cert, key, opts, cb) {
	assert.object(cert, 'cert');
	assert.ok(sshpk.Certificate.isCertificate(cert, [1, 0]),
	    'cert must be an sshpk.Certificate');
	assert.object(key, 'key');
	assert.ok(sshpk.PrivateKey.isPrivateKey(key, [1, 2]),
	    'key must be an sshpk.PrivateKey');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	assert.optionalNumber(opts.expires, 'options.expires');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {
		type: 'add-identity',
		privateKey: certToBuffer(cert, key),
		comment: cert.comment || key.comment || ''
	};
	if (opts.expires !== undefined) {
		frame.type = 'add-identity-constrained';
		frame.constraints = [
			{type: 'lifetime', seconds: opts.expires}
		];
	}
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent add-identity command ' +
			    'failed (not supported or invalid key?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};

Client.prototype.addKey = function (key, opts, cb) {
	assert.object(key, 'key');
	assert.ok(sshpk.PrivateKey.isPrivateKey(key, [1, 2]),
	    'key must be an sshpk.PrivateKey');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	assert.optionalNumber(opts.expires, 'options.expires');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {
		type: 'add-identity',
		privateKey: key.toBuffer('rfc4253'),
		comment: key.comment || ''
	};
	if (opts.expires !== undefined) {
		frame.type = 'add-identity-constrained';
		frame.constraints = [
			{type: 'lifetime', seconds: opts.expires}
		];
	}
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent add-identity command ' +
			    'failed (not supported, invalid key or ' +
			    'constraint/expiry not supported?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};

Client.prototype.removeKey = function (key, opts, cb) {
	assert.object(key, 'key');
	assert.ok(sshpk.Key.isKey(key, [1, 3]), 'key must be an sshpk.Key');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {
		type: 'remove-identity',
		publicKey: key.toBuffer('rfc4253')
	};
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent remove-identity command ' +
			    'failed (key not found, or operation not ' +
			    'supported?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};

Client.prototype.removeAllKeys = function (opts, cb) {
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {type: 'remove-all-identities'};
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent remote-all-identities ' +
			    'command failed (not supported?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};

Client.prototype.lock = function (pw, opts, cb) {
	assert.string(pw, 'password');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {
		type: 'lock',
		password: pw
	};
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent lock command failed ' +
			    '(empty or invalid password?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};

Client.prototype.unlock = function (pw, opts, cb) {
	assert.string(pw, 'password');
	if (typeof (opts) === 'function' && cb === undefined) {
		cb = opts;
		opts = {};
	}
	assert.object(opts, 'options');
	assert.optionalNumber(opts.timeout, 'options.timeout');
	var timeout = opts.timeout || this.timeout;
	assert.func(cb, 'callback');

	var frame = {
		type: 'unlock',
		password: pw
	};
	var resps = ['success', 'failure'];

	this.doRequest(frame, resps, timeout, function (err, resp) {
		if (err) {
			cb(err);
			return;
		}
		if (resp.type === 'failure') {
			cb(new Error('SSH agent unlock command failed ' +
			    '(invalid password?)'));
			return;
		}
		assert.strictEqual(resp.type, 'success');
		cb(null);
	});
};


module.exports = Client;
