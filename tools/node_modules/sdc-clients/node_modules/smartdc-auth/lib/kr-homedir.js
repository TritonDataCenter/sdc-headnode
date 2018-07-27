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

module.exports = KeyRingHomeDirPlugin;

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

function KeyRingHomeDirPlugin(kr, opts) {
	KeyRingPlugin.call(this, kr, opts);
	var path;

	if (typeof (opts.keyDir) === 'string') {
		this.hdp_path = opts.keyDir;

	} else {
		if (process.platform === 'win32') {
			path = process.env.USERPROFILE;
		} else {
			path = process.env.HOME;
		}

		if (!path) {
			throw (new Error('cannot find HOME dir ' +
			    '(HOME/USERPROFILE is not set)'));
		}

		path = mod_path.join(path, '.ssh');

		this.hdp_path = path;
	}
}
mod_util.inherits(KeyRingHomeDirPlugin, KeyRingPlugin);

KeyRingHomeDirPlugin.shortName = 'homedir';

KeyRingHomeDirPlugin.prototype.listKeys = function (cb) {
	var keys = [];
	this._iter(function (kp, next, finish) {
		keys.push(kp);
		next();
	}, function (err) {
		if (err && keys.length < 1) {
			cb(err);
		}
		cb(null, keys);
	});
};

KeyRingHomeDirPlugin.prototype.findKey = function (fp, cb) {
	mod_assert.ok(mod_sshpk.Fingerprint.isFingerprint(fp));
	var keys = [];
	this._iter(function (kp, next, finish) {
		if (fp.matches(kp.getPublicKey())) {
			keys.push(kp);
			finish();
		} else {
			next();
		}
	}, function (err) {
		if (err && keys.length < 1) {
			cb(err);
			return;
		}
		if (keys.length < 1) {
			cb(new mod_errors.KeyNotFoundError(fp, ['$HOME/.ssh']));
			return;
		}
		cb(null, keys);
	});
};

KeyRingHomeDirPlugin.prototype._iter = function (each, cb) {
	mod_assert.func(each);
	mod_assert.func(cb);

	var self = this;
	var skip = false;
	var path = this.hdp_path;

	mod_fs.readdir(path, function (err, files) {
		if (err) {
			cb(err);
			return;
		}

		var allKeyPaths = [];
		(files || []).forEach(function (f) {
			/*
			 * If we have a .pub file and a matching private key,
			 * consider them as a pair (see below).
			 */
			var m = f.match(/(.+)\.pub$/);
			if (m && files.indexOf(m[1]) !== -1) {
				allKeyPaths.push({
					public: mod_path.join(path, f),
					private: mod_path.join(path, m[1])
				});
				return;
			}
			if (m) {
				allKeyPaths.push({
					public: mod_path.join(path, f)
				});
				return;
			}
			/*
			 * If the name contains id_ (but doesn't end with .pub)
			 * and there is no matching public key, use it as a
			 * solo private key.
			 */
			var m2 = f.match(/(^|[^a-zA-Z])id_/);
			if (!m && m2 && files.indexOf(f + '.pub') === -1) {
				allKeyPaths.push({
					private: mod_path.join(path, f)
				});
				return;
			}
		});

		/*
		 * When we have both a public and private key file, read in the
		 * .pub file first to do the fingerprint match. If that
		 * succeeds, read in and validate that the private key file
		 * matches it.
		 *
		 * This also ensures we fail early and give a sensible error if,
		 * e.g. the specified key is password-protected.
		 */
		function readPublicKey(keyPaths, kcb) {
			mod_fs.readFile(keyPaths.public,
			    function (kerr, blob) {
				if (kerr) {
					kcb(kerr);
					return;
				}

				try {
					var key = mod_sshpk.parseKey(blob,
					    'ssh', keyPaths.public);
				} catch (e) {
					kcb(e);
					return;
				}

				if (keyPaths.private === undefined) {
					var pubSrc = mod_path.basename(
					    keyPaths.public);
					var kp = new KeyPair(self.krp_kr, {
						plugin: 'homedir',
						source: pubSrc,
						public: key
					    });
					each(kp, kcb, function () {
						skip = true;
						kcb();
					});
					return;
				}

				readPrivateKey(keyPaths, function (pkerr, pk) {
					var src = mod_path.basename(
					    keyPaths.private);
					if (pkerr && pkerr.name ===
					    'KeyEncryptedError') {
						var lkp = new LockedKeyPair(
						    self.krp_kr, {
							plugin: 'homedir',
							source: src,
							public: key,
							privateData: pk,
							privateFormat: 'pem'
						    });
						each(lkp, kcb, function () {
							skip = true;
							kcb();
						});
						return;
					}
					if (pkerr) {
						kcb(pkerr);
						return;
					}

					var kkp = new KeyPair(self.krp_kr, {
						plugin: 'homedir',
						source: src,
						public: key,
						private: pk
					    });
					each(kkp, kcb, function () {
						skip = true;
						kcb();
					});
				}, true);
			});
		}

		function readPrivateKey(keyPaths, kcb, inPublic) {
			mod_fs.readFile(keyPaths.private,
			    function (kerr, blob) {
				if (kerr) {
					kcb(kerr);
					return;
				}

				try {
					var key = mod_sshpk.parsePrivateKey(
					    blob, 'pem', keyPaths.private);
				} catch (e) {
					kcb(e, blob);
					return;
				}

				if (!inPublic) {
					var pub = key.toPublic();
					var src = mod_path.basename(
					    keyPaths.private);
					pub.comment = src;
					var kp = new KeyPair(self.krp_kr, {
						plugin: 'homedir',
						source: src,
						public: pub,
						private: key
					    });
					each(kp, kcb, function () {
						skip = true;
						kcb(null, key);
					});
				} else {
					kcb(null, key);
				}
			});
		}

		function processKey(keyPaths, kcb) {
			if (skip) {
				kcb();
				return;
			}
			/*
			 * Stat the file first to ensure we don't read from any
			 * sockets or crazy huge files that ended up in
			 * $HOME/.ssh (it happens).
			 *
			 * It's possible that the file could change between our
			 * stat here and when we open it in readPublicKey/
			 * readPrivateKey. Doing something about it is more
			 * effort than it's worth.
			 */
			if (keyPaths.public) {
				mod_fs.stat(keyPaths.public,
				    function (serr, stats) {
					if (serr) {
						kcb(serr);
						return;
					}
					if (stats.isFile() &&
					    stats.size < MAX_PUBKEY_SIZE) {
						readPublicKey(keyPaths, kcb);
					} else {
						kcb(new Error(keyPaths.public +
						    ' is not a regular file, ' +
						    'or size is too big to be' +
						    ' an SSH public key.'));
					}
				});
			} else {
				mod_fs.stat(keyPaths.private,
				    function (serr, stats) {
					if (serr) {
						kcb(serr);
						return;
					}
					if (stats.isFile() &&
					    stats.size < MAX_PRIVKEY_SIZE) {
						readPrivateKey(keyPaths, kcb);
					} else {
						kcb(new Error(keyPaths.private +
						    ' is not a regular file, ' +
						    'or size is too big to be' +
						    ' an SSH private key.'));
					}
				});
			}
		}

		var opts = {
			inputs: allKeyPaths,
			func: processKey
		};
		mod_vasync.forEachParallel(opts, cb);
	});
};
