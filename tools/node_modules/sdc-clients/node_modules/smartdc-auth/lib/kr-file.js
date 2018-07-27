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

module.exports = KeyRingFilePlugin;

var mod_util = require('util');
var mod_assert = require('assert-plus');
var mod_sshpk = require('sshpk');
var mod_fs = require('fs');
var mod_path = require('path');
var mod_errors = require('./errors');
var KeyRingPlugin = require('./krplugin');
var mod_vasync = require('vasync');

var mod_keypair = require('./keypair');
var KeyPair = mod_keypair.KeyPair;
var LockedKeyPair = mod_keypair.LockedKeyPair;

/*
 * These are max file sizes for pub/private keys, to avoid buffering in huge
 * files that clearly are not keys.
 */
var MAX_PUBKEY_SIZE = 65536;
var MAX_PRIVKEY_SIZE = 131072;

function KeyRingFilePlugin(kr, opts) {
	KeyRingPlugin.call(this, kr, opts);
	mod_assert.string(opts.keyPath, 'options.keyPath');
	this.krf_path = opts.keyPath;
	this.krf_kr = kr;
}
mod_util.inherits(KeyRingFilePlugin, KeyRingPlugin);

KeyRingFilePlugin.shortName = 'file';

KeyRingFilePlugin.prototype.listKeys = function (cb) {
	this._load(function (err, kp) {
		if (err) {
			cb(err);
			return;
		}
		cb(null, [kp]);
	});
};

KeyRingFilePlugin.prototype.findKey = function (fp, cb) {
	mod_assert.ok(mod_sshpk.Fingerprint.isFingerprint(fp));
	var self = this;
	var keys = [];
	this._load(function (err, kp) {
		if (err) {
			cb(err);
			return;
		}
		if (fp.matches(kp.getPublicKey())) {
			keys.push(kp);
			cb(null, keys);
		} else {
			cb(new mod_errors.KeyNotFoundError(fp,
			    [self.krf_path]));
		}
	});
};

KeyRingFilePlugin.prototype._load = function (cb) {
	mod_assert.func(cb);

	var self = this;
	var path = this.krf_path;
	var src = mod_path.basename(path);

	/*
	 * This might seem like a TOCTOU issue, stat'ing the file before
	 * reading it. But we're just trying to be helpful here, not really
	 * depending on this result for correctness.
	 */

	mod_fs.stat(path, function (serr, stats) {
		if (serr) {
			cb(serr);
			return;
		}
		if (!stats.isFile()) {
			cb(new Error(path + ' is not a regular file'));
			return;
		}
		if (stats.size >= MAX_PUBKEY_SIZE) {
			cb(new Error(path + ' is too large to be an SSH ' +
			    'public key file'));
			return;
		}

		tryReadKey();
	});

	function tryReadKey() {
		mod_fs.readFile(path, function (kerr, blob) {
			if (kerr) {
				cb(kerr);
				return;
			}

			try {
				var key = mod_sshpk.parsePrivateKey(blob,
				    'auto', path);
			} catch (e) {
				if (e.name === 'KeyEncryptedError') {
					tryReadPub(blob);
					return;
				}
				cb(e);
				return;
			}
			var kkp = new KeyPair(self.krf_kr, {
			    plugin: 'file',
			    source: src,
			    public: key.toPublic(),
			    private: key
			});
			cb(null, kkp);
		});
	}

	function tryReadPub(privBlob) {
		mod_fs.readFile(path + '.pub', function (kerr, blob) {
			if (kerr) {
				cb(kerr);
				return;
			}

			try {
				var key = mod_sshpk.parseKey(blob, 'auto',
				    path + '.pub');
			} catch (e) {
				cb(e);
				return;
			}
			var lkp = new LockedKeyPair(self.krf_kr, {
			    plugin: 'file',
			    source: src,
			    public: key,
			    privateData: privBlob,
			    privateFormat: 'auto'
			});
			cb(null, lkp);
		});
	}
};
