/*
 * Copyright 2016 Joyent, Inc., All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE
 */

var mod_assert = require('assert-plus');
var mod_httpsig = require('http-signature');
var mod_sshpk = require('sshpk');
var mod_clone = require('clone');

var KeyRing = require('./keyring');

var mod_keypair = require('./keypair');
var KeyPair = mod_keypair.KeyPair;
var LockedKeyPair = mod_keypair.LockedKeyPair;

var mod_errors = require('./errors');

module.exports = {
	KeyRing: KeyRing,
	KeyNotFoundError: mod_errors.KeyNotFoundError,

	/*
	 * These functions constitute the legacy API for compatibility with
	 * previous releases.
	 */
	cliSigner: cliSigner,
	privateKeySigner: privateKeySigner,
	sshAgentSigner: sshAgentSigner,
	loadSSHKey: loadSSHKey,
	signUrl: signUrl,
	requestSigner: requestSigner
};

/* This is the legacy API that we emulate for compatibility. */

function loadSSHKey(fp, cb) {
	if (typeof (fp) === 'string')
		fp = mod_sshpk.parseFingerprint(fp);
	mod_assert.object(fp, 'fingerprint');
	mod_assert.func(cb, 'callback');

	var kr = new KeyRing({ plugins: ['homedir'] });
	kr.findSigningKeyPair(fp, function (err, kp) {
		if (err) {
			cb(err);
			return;
		}
		try {
			var key = kp.getPrivateKey();
		} catch (e) {
			cb(e);
			return;
		}
		cb(null, key);
	});
}

function privateKeySigner(options) {
	mod_assert.object(options, 'options');
	if (typeof (options.key) !== 'string' &&
	    !Buffer.isBuffer(options.key)) {
		throw (new Error('options.key (a String or Buffer) is ' +
		    'required'));
	}
	mod_assert.string(options.key, 'options.key');
	mod_assert.string(options.user, 'options.user');
	mod_assert.optionalString(options.subuser, 'options.subuser');
	mod_assert.optionalString(options.keyId, 'options.keyId');

	var key = mod_sshpk.parsePrivateKey(options.key);
	var kp = KeyPair.fromPrivateKey(key);
	return (kp.createSign(options));
}

function sshAgentSigner(options) {
	mod_assert.object(options, 'options');
	mod_assert.string(options.keyId, 'options.keyId');
	mod_assert.string(options.user, 'options.user');
	mod_assert.optionalString(options.subuser, 'options.subuser');
	mod_assert.optionalObject(options.sshAgentOpts, 'options.sshAgentOpts');

	var fp = mod_sshpk.parseFingerprint(options.keyId);
	var kr = new KeyRing({ plugins: ['agent'] });

	return (signerWrapper(fp, kr, options));
}

function cliSigner(options) {
	mod_assert.object(options, 'options');
	mod_assert.string(options.keyId, 'options.keyId');
	mod_assert.string(options.user, 'options.user');
	mod_assert.optionalString(options.subuser, 'options.subuser');
	mod_assert.optionalObject(options.sshAgentOpts, 'options.sshAgentOpts');

	var fp = mod_sshpk.parseFingerprint(options.keyId);
	var kr = new KeyRing();

	return (signerWrapper(fp, kr, options));
}

function requestSigner(options) {
	mod_assert.object(options, 'options');
	mod_assert.optionalString(options.keyId, 'options.keyId');
	mod_assert.optionalFunc(options.sign, 'options.sign');
	mod_assert.optionalString(options.user, 'options.user');
	mod_assert.optionalString(options.subuser, 'options.subuser');
	mod_assert.optionalObject(options.sshAgentOpts, 'options.sshAgentOpts');
	mod_assert.optionalBool(options.mantaSubUser, 'options.mantaSubUser');

	var sign = options.sign || cliSigner(options);

	function rsign(data, cb) {
		sign(data, function (err, res) {
			if (res) {
				var user = options.user || sign.user ||
				    res.user;
				var subuser = options.subuser || sign.subuser ||
				    res.subuser;
				mod_assert.string(user, 'user');
				if (subuser) {
					if (options.mantaSubUser)
						user += '/' + subuser;
					else
						user += '/users/' + subuser;
				}
				var keyId = '/' + user + '/keys/' + res.keyId;
				res = {
				    algorithm: res.algorithm,
				    keyId: keyId,
				    signature: res.signature,
				    user: user,
				    subuser: subuser
				};
			}
			cb(err, res);
		});
	}

	return (mod_httpsig.createSigner({ sign: rsign }));
}

function signerWrapper(fp, kr, options) {
	var kpsign;

	function sign(data, cb) {
		if (kpsign === undefined) {
			kr.findSigningKeyPair(fp, function (err, kp) {
				if (err) {
					cb(err);
					return;
				}
				kpsign = kp.createSign(options);
				sign.keypair = kp;
				kpsign(data, cb);
			});
			return;
		}
		kpsign(data, cb);
	}

	Object.defineProperty(sign, 'keyId', {
	    get: function () {
		if (kpsign === undefined)
			return (undefined);
		return (kpsign.keyId);
	    }
	});
	sign.user = options.user;
	sign.subuser = options.subuser;
	sign.getKey = function (cb) {
		if (kpsign === undefined) {
			kr.findSigningKeyPair(fp, function (err, kp) {
				kpsign = kp.createSign(options);
				kpsign.getKey(cb);
			});
			return;
		}
		kpsign.getKey(cb);
	};
	sign.keyring = kr;
	sign.fp = fp;

	return (sign);
}

function rfc3986(str) {
	return (encodeURIComponent(str)
	    .replace(/[!'()]/g, escape)
	    /* JSSTYLED */
	    .replace(/\*/g, '%2A'));
}

/*
 * Creates a presigned URL.
 *
 * Invoke with a signing callback (like other client APIs) and the keys/et al
 * needed to actually form a valid presigned request.
 *
 * Parameters:
 * - host, keyId, user: see other client APIs
 * - sign: needs to have a .getKey() (all the provided signers in smartdc-auth
 *         are fine)
 * - path: URL path to sign
 * - query: optional HTTP query parameters to include on the URL
 * - expires: the expire time of the URL, in seconds since the Unix epoch
 * - mantaSubUser: set to true if using sub-users with Manta
 */
function signUrl(opts, cb) {
	mod_assert.object(opts, 'options');
	mod_assert.optionalNumber(opts.expires, 'options.expires');
	mod_assert.string(opts.host, 'options.host,');
	mod_assert.string(opts.keyId, 'options.keyId');
	mod_assert.string(opts.user, 'options.user');
	mod_assert.string(opts.path, 'options.path');
	mod_assert.optionalObject(opts.query, 'options.query');
	mod_assert.optionalArrayOfString(opts.role, 'options.role');
	mod_assert.optionalArrayOfString(opts['role-tag'],
	    'options[\'role-tag\']');
	mod_assert.optionalString(opts.subuser, 'opts.subuser');
	mod_assert.func(opts.sign, 'options.sign');
	mod_assert.func(opts.sign.getKey, 'options.sign.getKey');
	mod_assert.func(cb, 'callback');
	mod_assert.optionalBool(opts.mantaSubUser, 'options.mantaSubUser');
	mod_assert.optionalString(opts.algorithm, 'options.algorithm');

	if (opts.mantaSubUser && opts.subuser !== undefined)
		opts.user = opts.user + '/' + opts.subuser;
	else if (opts.subuser !== undefined)
		opts.user = opts.user + '/user/' + opts.subuser;

	if (opts.method !== undefined) {
		if (Array.isArray(opts.method)) {
			mod_assert.ok(opts.method.length >= 1);
			opts.method.forEach(function (m) {
				mod_assert.string(m, 'options.method');
			});
		} else {
			mod_assert.string(opts.method, 'options.method');
			opts.method = [opts.method];
		}
	} else {
		opts.method = ['GET', 'HEAD'];
	}
	opts.method.sort();
	var method = opts.method.join(',');

	var q = mod_clone(opts.query || {});
	q.expires = (opts.expires ||
	    Math.floor(((Date.now() + (1000 * 300))/1000)));

	if (opts.role)
		q.role = opts.role.join(',');

	if (opts['role-tag'])
		q['role-tag'] = opts['role-tag'].join(',');

	if (opts.method.length > 1)
		q.method = method;

	opts.sign.getKey(function (err, key) {
		if (err) {
			cb(err);
			return;
		}

		var fp = key.fingerprint('md5').toString('hex');
		q.keyId = '/' + opts.user + '/keys/' + fp;

		q.algorithm = opts.algorithm || opts.sign.algorithm;
		if (q.algorithm === undefined) {
			q.algorithm = key.type + '-' +
			    key.defaultHashAlgorithm();
		}
		q.algorithm = q.algorithm.toUpperCase();

		var line =
		    method + '\n' +
		    opts.host + '\n' +
		    opts.path + '\n';

		var str = Object.keys(q).sort(function (a, b) {
			return (a.localeCompare(b));
		}).map(function (k) {
			return (rfc3986(k) + '=' + rfc3986(q[k]));
		}).join('&');

		line += str;

		if (opts.log)
			opts.log.debug('signUrl: signing -->\n%s', line);

		opts.sign(line, function onSignature(serr, obj) {
			if (serr) {
				cb(serr);
			} else {
				if (obj.algorithm.toUpperCase() !==
				    q.algorithm) {
					if (opts.algorithm === undefined) {
						opts.algorithm = obj.algorithm;
						signUrl(opts, cb);
					} else {
						cb(new Error('The algorithm ' +
						    q.algorithm + ' could not' +
						    ' be used with this key ' +
						    '(try ' + obj.algorithm.
						    toUpperCase() + ')'));
					}
					return;
				}
				var u = opts.path + '?' + str + '&signature=' +
				    rfc3986(obj.signature);
				cb(null, u);
			}
		});
	});
}
