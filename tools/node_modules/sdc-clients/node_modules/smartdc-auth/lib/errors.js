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
	KeyNotFoundError: KeyNotFoundError
};

var mod_assert = require('assert-plus');
var mod_util = require('util');

function KeyNotFoundError(fp, srcs) {
	mod_assert.object(fp, 'fingerprint');
	mod_assert.arrayOfString(srcs, 'sources');
	if (Error.captureStackTrace)
		Error.captureStackTrace(this, KeyNotFoundError);
	this.name = 'KeyNotFoundError';
	this.fingerprint = fp;
	this.sources = srcs;
	this.message = 'SSH key with fingerprint "' + fp.toString() + '" ' +
	    'could not be located in ' + srcs.join(' or ');
}
mod_util.inherits(KeyNotFoundError, Error);
/*
 * Used to condense multiple KeyNotFoundErrors into one, so that we can
 * produce a single error that covers everything. Joins them together by
 * concatenating their .sources lists.
 */
KeyNotFoundError.join = function (errs) {
	mod_assert.arrayOfObject(errs, 'errors');
	var fp = errs[0].fingerprint;
	var srcs = errs[0].sources;
	for (var i = 1; i < errs.length; ++i) {
		mod_assert.ok(errs[i] instanceof KeyNotFoundError);
		mod_assert.strictEqual(errs[i].fingerprint, fp);
		srcs = srcs.concat(errs[i].sources);
	}
	return (new KeyNotFoundError(fp, srcs));
};
