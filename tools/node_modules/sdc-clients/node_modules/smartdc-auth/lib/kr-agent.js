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

module.exports = KeyRingAgentPlugin;

var mod_util = require('util');
var mod_assert = require('assert-plus');
var mod_sshpk = require('sshpk');
var mod_agent = require('sshpk-agent');
var mod_vasync = require('vasync');
var mod_errors = require('./errors');
var KeyRingPlugin = require('./krplugin');

var mod_keypair = require('./keypair');
var KeyPair = mod_keypair.KeyPair;
var LockedKeyPair = mod_keypair.LockedKeyPair;

function KeyRingAgentPlugin(kr, opts) {
	KeyRingPlugin.call(this, kr, opts);
	mod_assert.optionalObject(opts.sshAgentOpts);

	this.kra_error = undefined;
	this.kra_agent = new mod_agent.Client(opts.sshAgentOpts);
}
mod_util.inherits(KeyRingAgentPlugin, KeyRingPlugin);

KeyRingAgentPlugin.prototype.listKeys = function (cb) {
	var self = this;
	if (!this.kra_agent) {
		cb(null, []);
		return;
	}
	this.kra_agent.listKeys(function (err, keys) {
		if (err) {
			cb(err);
			return;
		}
		var kps = keys.map(function (k) {
			return (new AgentKeyPair(self.krp_kr, self.kra_agent, {
			    plugin: 'agent', public: k }));
		});
		cb(null, kps);
	});
};

KeyRingAgentPlugin.shortName = 'agent';

KeyRingAgentPlugin.prototype.findKey = function (fp, cb) {
	mod_assert.ok(mod_sshpk.Fingerprint.isFingerprint(fp));
	var self = this;
	if (!this.kra_agent) {
		cb(new mod_errors.KeyNotFoundError(fp, ['SSH agent']));
		return;
	}
	this.kra_agent.listKeys(function (err, keys) {
		if (err) {
			cb(err);
			return;
		}
		for (var i = 0; i < keys.length; ++i) {
			if (fp.matches(keys[i])) {
				var kp = new AgentKeyPair(self.krp_kr,
				    self.kra_agent, { plugin: 'agent',
				    public: keys[i] });
				cb(null, [kp]);
				return;
			}
		}
		cb(new mod_errors.KeyNotFoundError(fp, ['SSH agent']));
	});
};

function AgentKeyPair(kr, agent, opts) {
	KeyPair.call(this, kr, opts);
	this.akp_agent = agent;
}
mod_util.inherits(AgentKeyPair, KeyPair);

AgentKeyPair.prototype.getPrivateKey = function () {
	throw (new Error('Agent private keys cannot be directly retrieved'));
};

AgentKeyPair.prototype.canSign = function () {
	return (true);
};

AgentKeyPair.prototype.createSign = function (opts) {
	mod_assert.object(opts, 'options');
	mod_assert.optionalString(opts.algorithm, 'options.algorithm');
	mod_assert.optionalString(opts.keyId, 'options.keyId');
	mod_assert.string(opts.user, 'options.user');
	mod_assert.optionalString(opts.subuser, 'options.subuser');
	mod_assert.optionalBool(opts.mantaSubUser, 'options.mantaSubUser');

	var pub = this.getPublicKey();
	var keyId = this.getKeyId();
	var alg = opts.algorithm;
	var algParts = alg ? alg.toLowerCase().split('-') : [];

	if (algParts[0] && algParts[0] !== pub.type) {
		throw (new Error('Requested algorithm ' + alg + ' is ' +
		    'not supported with a key of type ' + pub.type));
	}

	var self = this;
	var cache = this.skp_kr.getSignatureCache();

	function sign(data, cb) {
		mod_assert.string(data, 'data');
		mod_assert.func(cb, 'callback');

		var ck = { key: pub, data: data };
		if (cache.get(ck, cb))
			return;
		cache.registerPending(ck);

		self.akp_agent.sign(pub, data, function (err, sig) {
			if (err) {
				cache.put(ck, err);
				cb(err);
				return;
			}

			var res = {
			    algorithm: pub.type + '-' + sig.hashAlgorithm,
			    keyId: keyId,
			    signature: sig.toString(),
			    user: opts.user,
			    subuser: opts.subuser
			};
			sign.algorithm = res.algorithm;

			cache.put(ck, null, res);
			cb(null, res);
		});
	}

	sign.keyId = keyId;
	sign.user = opts.user;
	sign.subuser = opts.subuser;
	sign.getKey = function (cb) {
		cb(null, self.skp_public);
	};
	return (sign);
};
