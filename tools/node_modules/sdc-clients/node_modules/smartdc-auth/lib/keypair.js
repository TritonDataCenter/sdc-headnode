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

module.exports = {
	KeyPair: SDCKeyPair,
	LockedKeyPair: SDCLockedKeyPair
};

var mod_assert = require('assert-plus');
var mod_sshpk = require('sshpk');
var mod_util = require('util');
var mod_httpsig = require('http-signature');

var KeyRing = require('./keyring');

function SDCKeyPair(kr, opts) {
	mod_assert.object(kr, 'keyring');
	mod_assert.ok(kr instanceof KeyRing,
	    'keyring instanceof KeyRing');
	this.skp_kr = kr;

	mod_assert.object(opts, 'options');
	mod_assert.string(opts.plugin, 'options.plugin');
	mod_assert.optionalString(opts.source, 'options.source');

	this.plugin = opts.plugin;
	this.source = opts.source;
	this.comment = '';

	if (opts.public !== undefined) {
		mod_assert.ok(mod_sshpk.Key.isKey(opts.public),
		    'options.public must be a sshpk.Key instance');
		this.comment = opts.public.comment;
	}
	this.skp_public = opts.public;
	if (opts.private !== undefined) {
		mod_assert.ok(mod_sshpk.PrivateKey.isPrivateKey(opts.private),
		    'options.private must be a sshpk.PrivateKey instance');
	}
	this.skp_private = opts.private;
}

SDCKeyPair.fromPrivateKey = function (key) {
	mod_assert.object(key, 'key');
	mod_assert.ok(mod_sshpk.PrivateKey.isPrivateKey(key),
	    'key is a PrivateKey');

	var kr = new KeyRing({ plugins: [] });
	var kp = new SDCKeyPair(kr, {
		plugin: 'none',
		private: key,
		public: key.toPublic()
	});
	return (kp);
};

SDCKeyPair.prototype.canSign = function () {
	return (this.skp_private !== undefined);
};

SDCKeyPair.prototype.createRequestSigner = function (opts) {
	mod_assert.string(opts.user, 'options.user');
	mod_assert.optionalString(opts.subuser, 'options.subuser');
	mod_assert.optionalBool(opts.mantaSubUser, 'options.mantaSubUser');

	var sign = this.createSign(opts);

	var user = opts.user;
	if (opts.subuser) {
		if (opts.mantaSubUser)
			user += '/' + opts.subuser;
		else
			user += '/users/' + opts.subuser;
	}
	var keyId = '/' + user + '/keys/' + this.getKeyId();

	function rsign(data, cb) {
		sign(data, function (err, res) {
			if (res)
				res.keyId = keyId;
			cb(err, res);
		});
	}
	return (mod_httpsig.createSigner({ sign: rsign }));
};

SDCKeyPair.prototype.createSign = function (opts) {
	mod_assert.object(opts, 'options');
	mod_assert.optionalString(opts.algorithm, 'options.algorithm');
	mod_assert.optionalString(opts.keyId, 'options.keyId');
	mod_assert.string(opts.user, 'options.user');
	mod_assert.optionalString(opts.subuser, 'options.subuser');
	mod_assert.optionalBool(opts.mantaSubUser, 'options.mantaSubUser');

	if (this.skp_private === undefined) {
		throw (new Error('Private key for this key pair is ' +
		    'unavailable (because, e.g. only a public key was ' +
		    'found and no matching private half)'));
	}
	var key = this.skp_private;
	var keyId = this.getKeyId();
	var alg = opts.algorithm;
	var algParts = alg ? alg.toLowerCase().split('-') : [];

	if (algParts[0] && algParts[0] !== key.type) {
		throw (new Error('Requested algorithm ' + alg + ' is ' +
		    'not supported with a key of type ' + key.type));
	}

	var self = this;
	var cache = this.skp_kr.getSignatureCache();
	function sign(data, cb) {
		mod_assert.string(data, 'data');
		mod_assert.func(cb, 'callback');

		var ck = { key: key, data: data };
		if (cache.get(ck, cb))
			return;
		cache.registerPending(ck);

		/*
		 * We can throw in here if the hash algorithm we were told to
		 * use in 'algorithm' is invalid. Return it as a normal error.
		 */
		var signer, sig;
		try {
			signer = self.skp_private.createSign(algParts[1]);
			signer.update(data);
			sig = signer.sign();
		} catch (e) {
			cache.put(ck, e);
			cb(e);
			return;
		}

		var res = {
		    algorithm: key.type + '-' + sig.hashAlgorithm,
		    keyId: keyId,
		    signature: sig.toString(),
		    user: opts.user,
		    subuser: opts.subuser
		};
		sign.algorithm = res.algorithm;

		cache.put(ck, null, res);

		cb(null, res);
	}

	sign.keyId = keyId;
	sign.user = opts.user;
	sign.subuser = opts.subuser;
	sign.getKey = function (cb) {
		cb(null, self.skp_private);
	};
	return (sign);
};

SDCKeyPair.prototype.getKeyId = function () {
	return (this.skp_public.fingerprint('md5').toString('hex'));
};

SDCKeyPair.prototype.getPublicKey = function () {
	return (this.skp_public);
};

SDCKeyPair.prototype.getPrivateKey = function () {
	return (this.skp_private);
};

SDCKeyPair.prototype.isLocked = function () {
	return (false);
};

SDCKeyPair.prototype.unlock = function (passphrase) {
	throw (new Error('Keypair is not locked'));
};


function SDCLockedKeyPair(kr, opts) {
	SDCKeyPair.call(this, kr, opts);

	mod_assert.buffer(opts.privateData, 'options.privateData');
	this.lkp_privateData = opts.privateData;
	mod_assert.string(opts.privateFormat, 'options.privateFormat');
	this.lkp_privateFormat = opts.privateFormat;
	this.lkp_locked = true;
}
mod_util.inherits(SDCLockedKeyPair, SDCKeyPair);

SDCLockedKeyPair.prototype.createSign = function (opts) {
	if (this.lkp_locked) {
		throw (new Error('SSH private key ' +
		    this.getPublicKey().comment +
		    ' is locked (encrypted/password-protected). It must be ' +
		    'unlocked before use.'));
	}
	return (SDCKeyPair.prototype.createSign.call(this, opts));
};

SDCLockedKeyPair.prototype.createRequestSigner = function (opts) {
	if (this.lkp_locked) {
		throw (new Error('SSH private key ' +
		    this.getPublicKey().comment +
		    ' is locked (encrypted/password-protected). It must be ' +
		    'unlocked before use.'));
	}
	return (SDCKeyPair.prototype.createRequestSigner.call(this, opts));
};

SDCLockedKeyPair.prototype.canSign = function () {
	return (true);
};

SDCLockedKeyPair.prototype.getPrivateKey = function () {
	if (this.lkp_locked) {
		throw (new Error('SSH private key ' +
		    this.getPublicKey().comment +
		    ' is locked (encrypted/password-protected). It must be ' +
		    'unlocked before use.'));
	}
	return (this.skp_private);
};

SDCLockedKeyPair.prototype.isLocked = function () {
	return (this.lkp_locked);
};

SDCLockedKeyPair.prototype.unlock = function (passphrase) {
	mod_assert.ok(this.lkp_locked);
	this.skp_private = mod_sshpk.parsePrivateKey(this.lkp_privateData,
	    this.lkp_privateFormat, { passphrase: passphrase });
	mod_assert.ok(this.skp_public.fingerprint('sha512').matches(
	    this.skp_private));
	this.lkp_locked = false;
};
