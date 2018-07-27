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

module.exports = SDCKeyRing;

var mod_assert = require('assert-plus');
var mod_vasync = require('vasync');
var mod_events = require('events');
var EventEmitter = mod_events.EventEmitter;
var mod_errors = require('./errors');
var mod_util = require('util');

/*
 * Keep this in rough order of performance, to make the logic in
 * findSigningKey() produce good results.
 */
var PLUGINS = ['file', 'homedir', 'agent'];

function SDCKeyRing(opts) {
	var self = this;
	var pluginReq = true;
	mod_assert.optionalObject(opts, 'options');
	if (opts === undefined)
		opts = {};
	mod_assert.optionalArrayOfString(opts.plugins, 'options.plugins');
	if (opts.plugins === undefined) {
		opts.plugins = PLUGINS;
		pluginReq = false;
	}

	this.skr_pluginNames = [];
	this.skr_plugins = [];
	opts.plugins.forEach(function (name) {
		mod_assert.ok(PLUGINS.indexOf(name) !== -1);
		var Plugin = require('./kr-' + name);
		try {
			var inst = new Plugin(self, opts);
			self.skr_plugins.push(inst);
			self.skr_pluginNames.push(name);
		} catch (e) {
			/*
			 * Only throw if the user specifically requested this
			 * plugin. Otherwise proceed without this plugin
			 * entirely. This handles the case where we just create
			 * a KeyRing with no options and expect it to still work
			 * and give us filesystem keys even though there's no
			 * SSH agent available (for example).
			 */
			if (pluginReq)
				throw (e);
		}
	});

	this.skr_cache = new SignatureCache();
}

SDCKeyRing.prototype.addPlugin = function (nameOrInstance, opts) {
	var instance, name;
	if (typeof (nameOrInstance) === 'string') {
		name = nameOrInstance;
		var Plugin = require('./kr-' + name);
		instance = new Plugin(this, opts);
	} else if (typeof (nameOrInstance) === 'object' &&
	    nameOrInstance !== null) {
		instance = nameOrInstance;
		name = instance.constructor.shortName ||
		    instance.constructor.name;
	}
	this.skr_plugins.push(instance);
	this.skr_pluginNames.push(name);
};

SDCKeyRing.prototype.getSignatureCache = function () {
	return (this.skr_cache);
};

SDCKeyRing.prototype.list = function (cb) {
	var keys = {};
	mod_vasync.forEachParallel({
		func: runPlugin,
		inputs: this.skr_plugins
	}, function (err) {
		if (err) {
			cb(err);
			return;
		}
		cb(null, keys);
	});
	function runPlugin(plugin, pcb) {
		plugin.listKeys(function (err, pairs) {
			if (err) {
				pcb(err);
				return;
			}
			pairs.forEach(function (pair) {
				var keyId = pair.getKeyId();
				if (keys[keyId] === undefined)
					keys[keyId] = [];
				keys[keyId].push(pair);
			});
			pcb();
		});
	}
};

SDCKeyRing.prototype.find = function (fp, cb) {
	var keys = [];
	mod_vasync.forEachParallel({
		func: runPlugin,
		inputs: this.skr_plugins
	}, function (err) {
		if (err && Array.isArray(err.ase_errors)) {
			var knfs = err.ase_errors.filter(function (e) {
				return (e.name === 'KeyNotFoundError');
			});
			if (knfs.length === err.ase_errors.length) {
				if (keys.length > 0) {
					cb(null, keys);
					return;
				}
				err = mod_errors.KeyNotFoundError.join(knfs);
			}
			cb(err);
			return;
		} else if (err) {
			cb(err);
			return;
		}
		cb(null, keys);
	});
	function runPlugin(plugin, pcb) {
		plugin.findKey(fp, function (err, pairs) {
			if (err) {
				pcb(err);
				return;
			}
			pairs.forEach(function (pair) {
				keys.push(pair);
			});
			pcb();
		});
	}
};

SDCKeyRing.prototype.findSigningKeyPair = function (fp, cb) {
	var self = this;
	this.find(fp, function (err, kps) {
		if (err) {
			cb(err);
			return;
		}
		kps = kps.filter(function (kp) {
			return (kp.canSign());
		}).sort(function (a, b) {
			/* Always prefer already-unlocked keys. */
			if (a.isLocked() && !b.isLocked())
				return (1);
			if (!a.isLocked() && b.isLocked())
				return (-1);
			/* Then preference in PLUGINS order. */
			var idxa = PLUGINS.indexOf(a.plugin);
			var idxb = PLUGINS.indexOf(b.plugin);
			if (idxa < idxb)
				return (-1);
			if (idxa > idxb)
				return (1);
			return (0);
		});
		if (kps.length < 1) {
			cb(new mod_errors.KeyNotFoundError(fp,
			    self.skr_pluginNames));
			return;
		}
		cb(null, kps[0]);
	});
};

SDCKeyRing.getPlugins = function () {
	return (PLUGINS.slice());
};

function SignatureCache(opts) {
	mod_assert.optionalObject(opts, 'options');
	opts = opts || {};
	mod_assert.optionalNumber(opts.expiry, 'options.expiry');

	this.expiry = opts.expiry || 10000;
	this.pending = new EventEmitter();
	this.pending.table = {};
	this.table = {};
	this.list = [];
}

function createCacheKey(opts) {
	mod_assert.object(opts, 'options');
	mod_assert.object(opts.key, 'options.key');
	mod_assert.string(opts.data, 'options.data');
	return (opts.key.fingerprint('sha256').toString() + '|' + opts.data);
}

SignatureCache.prototype.get = function get(opts, cb) {
	mod_assert.func(cb, 'callback');

	var k = createCacheKey(opts);

	var found = false;
	var self = this;

	function cachedResponse() {
		var val = self.table[k].value;
		cb(val.err, val.value);
	}

	if (this.table[k]) {
		found = true;
		process.nextTick(cachedResponse);
	} else if (this.pending.table[k]) {
		found = true;
		this.pending.once(k, cachedResponse);
	}

	return (found);
};

SignatureCache.prototype.registerPending = function (opts) {
	var k = createCacheKey(opts);
	this.pending.table[k] = true;
};

SignatureCache.prototype.put = function put(opts, err, v) {
	mod_assert.ok(v, 'value');

	var k = createCacheKey(opts);

	this.table[k] = {
	    time: new Date().getTime(),
	    value: { err: err, value: v }
	};

	if (this.pending.table[k])
		delete this.pending.table[k];

	this.pending.emit(k, v);
	this.purge();
};


SignatureCache.prototype.purge = function purge() {
	var list = [];
	var now = new Date().getTime();
	var self = this;

	Object.keys(this.table).forEach(function (k) {
		if (self.table[k].time + self.expiry < now)
			list.push(k);
	});

	list.forEach(function (k) {
		if (self.table[k])
			delete self.table[k];
	});
};


SignatureCache.prototype.toString = function toString() {
	var fmt = '[object SignatureCache<pending=%j, table=%j>]';
	return (mod_util.format(fmt, this.pending.table, this.table));
};
