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

module.exports = SDCKeyRingPlugin;

var mod_assert = require('assert-plus');
var mod_sshpk = require('sshpk');
var KeyRing = require('./keyring');

function SDCKeyRingPlugin(kr, opts) {
	mod_assert.object(kr, 'keyring');
	mod_assert.ok(kr instanceof KeyRing);
	this.krp_kr = kr;

	mod_assert.object(opts, 'options');
}

SDCKeyRingPlugin.prototype.listKeys = function (cb) {
	cb(new Error('This plugin does not implement listKeys'));
};

SDCKeyRingPlugin.prototype.findKey = function (fp, cb) {
	mod_assert.ok(mod_sshpk.Fingerprint.isFingerprint(fp));
	cb(new Error('This plugin does not implement findKey'));
};
