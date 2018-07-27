/*
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

/*
 * Copyright 2015, Joyent, Inc.
 */

/*
 * Limit, Offset, Marker Stream
 *
 * The purpose of this stream is to handle interfacing with systems that have a
 * combination of limits, and either offset and marker support. For example,
 * moray and the various SDC clients.
 *
 * Users provide a fetch function that is responsible for getting sets of
 * queries from the backend. The lomstream will make calls to the fetch function
 * for results when required. It ensures that only one request is outstanding at
 * any given time and takes care of keeping track of whether another call to the
 * fetch function is required to satisfy node.
 *
 * The lomstream has a couple distinct states:
 *
 * 1) Idle - This occurs when the stream is waiting for work to do. fetch() is
 * not running and node has not done its edge trigger call to _read(). When node
 * makes a call to _read() to trigger, we become active.
 *
 * 2) Active - This occurs when _read() has been edge triggered for the first
 * time. At this time, the lom_reading value is set to true. A call to fetch()
 * will be kicked off that will continue until the done callback from fetch
 * (lomFetchDoneCallback) is called.
 *
 * During this time, we'll receive a series of callbacks from the user. We will
 * push an item onto the stream once for each call to the datacb() and once for
 * each item in the results array.
 *
 * During the time that a fetch is ongoing, we keep track of the number of times
 * we get an edge triggered _read() from node. If during the push of the last
 * data item, we get an edge-triggered event, then we'll recursively call our
 * _read() function after we're done.
 *
 * If we don't have to trigger ourselves, then we'll just transition back to the
 * initial state and wait for node to call ourselves. Otherwise, if we were told
 * that we were done, we'll transition to a third state.
 *
 * 3) Done - This occurs when fetch() has indicated that there's nothing else to
 * do. We end the stream's input and we don't expect any future calls from node.
 *
 * 4) Error - If the fetch callback returns an error, then we'll end up in an
 * error state where we refuse to do anything else. When we get the error, we
 * save it and then emit to node.
 *
 * This can all be summarized in the following state machine diagram:
 *
 *                     . . _read() called  +-------+
 *                     .                   v       * . _read called
 *      +--------+     .          +----------+     |   while pushing
 *      |        |-----*--------->|          |-----+   last data item
 *      |  Idle  |                |  Active  |
 *      |        |<-------------- |          |
 *      +--------+                +----------+
 *                                  |     |
 *               +-----+------------+     * . . fetch() indicated
 *  fetch()  . . *                        v          no more data
 *  donecb()     v                  +--------+
 *  returned +---------+            |        |
 *  an error |         |            |  Done  |
 *           |  Error  |            |        |
 *           |         |            +--------+
 *           +---------+
 */

var mod_assert = require('assert-plus');
var mod_stream = require('stream');
var mod_util = require('util');
var mod_vstream = require('vstream');
var sprintf = require('extsprintf').sprintf;

var LOM_MIN_LIMIT = 1;
var LOM_MAX_LIMIT = 2147483647; /* INT32_MAX */
var LOM_RES_KEYS = [ 'done', 'results' ];

/*
 * Public interfaces
 */
exports.LOMStream = LOMStream;

/*
 * Given a set of user-passed stream options in "useroptions" (which may be
 * undefined) and a set of overrides (which must be a valid object), construct
 * an options object containing the union, with "overrides" overriding
 * "useroptions", without modifying either object.
 *
 * Note, this function originally came from joyent/dragnet. If this is modified,
 * it should really be factored out into its own common module.
 */
function streamOptions(useroptions, overrides, defaults)
{
	var streamoptions, k;

	streamoptions = {};
	if (defaults) {
		for (k in defaults)
			streamoptions[k] = defaults[k];
	}

	if (useroptions) {
		for (k in useroptions)
			streamoptions[k] = useroptions[k];
	}

	for (k in overrides)
		streamoptions[k] = overrides[k];

	return (streamoptions);
}

/*
 * Create a limit, offset, marker stream. We require the following options:
 *
 * fetch	A function that describes how to fetch data. The function will
 * 		be called as fetch(fetcharg, limitObj, datacb, donecb). The
 * 		limitObj will have limit set and one of offset and marker.
 * 		They mean:
 *
 * 			o offset	The offset to use for the request
 * 			o marker	The marker to use for the request
 * 			o limit		The limit to use for the request
 *
 * 		The datacb will be of the form datacb(obj). It should be used if
 * 		there's a single object for which data is available. If an error
 * 		occurs, then datacb() should not be called any additional times
 * 		and instead the donecb should be called with the error.
 *
 * 		The donecb will be of the form of donecb(err, result). The
 * 		result should be an object that has the form of:
 *
 * 			{
 * 				"done": <boolean>
 * 				"results": <array>
 *			}
 *
 *		The done boolean indicates that there will be no more results.
 *		The results array contains an array of items to emit. The type
 *		of the items is not important. The only times that results
 *		should be empty is when done is set to true or if all entries
 *		were pushed via the datacb(), then results may be empty.
 *
 *		The two different modes of passing results are designed to
 *		handle two different modes of clients. Using the data callback
 *		for each item is designed for a fetch() function which streams
 *		results. Where as the latter form is designed for a fetch() that
 *		batches results, eg. a rest API request that returns an array of
 *		limit objects.
 *
 *
 * limit	The maximum number of entries to grab at once.
 *
 * We require one of the following:
 *
 * offset	A boolean set to true to indicate that we should use offsets
 * marker	A function that given an object returns the marker from it.
 *
 * The following arguments are optional:
 *
 * fetcharg	An argument to be passed to the fetching function.
 *
 * streamOptions	Options to pass to the stream constructor
 */
function LOMStream(opts)
{
	var uoff, options;

	/* req args */
	mod_assert.func(opts.fetch, 'fetch argument is required');
	mod_assert.number(opts.limit, 'limit argument is required');
	mod_assert.ok(opts.limit >= LOM_MIN_LIMIT &&
	    opts.limit <= LOM_MAX_LIMIT, sprintf('limit must be in the range ' +
	    '[ %d, %d ]', LOM_MIN_LIMIT, LOM_MAX_LIMIT));
	mod_assert.ok((opts.limit | 0) === opts.limit, 'limit must be an ' +
	    'integer');

	mod_assert.optionalObject(opts.streamOptions,
	    'streamOptions must be an object');
	mod_assert.ok(opts.hasOwnProperty('offset') ||
	    opts.hasOwnProperty('marker'),
	    'one of offset and marker is required');

	mod_assert.ok(!(opts.hasOwnProperty('offset') &&
	    opts.hasOwnProperty('marker')),
	    'only one of offset and marker may be specified');

	if (opts.hasOwnProperty('offset')) {
		mod_assert.bool(opts.offset, 'offset must be a boolean');
		uoff = true;
	}

	if (opts.hasOwnProperty('marker')) {
		mod_assert.func(opts.marker, 'marker must be a function');
		uoff = false;
	}

	this.lom_reading = false;	/* Are we servicing _read()? */
	this.lom_error = null;		/* The error that occurred */
	this.lom_errored = false;	/* Is there an error on the stream? */
	this.lom_finished = false;	/* Did fetch() return that it's done? */
	this.lom_data = null;		/* Current data from fetch cb */
	this.lom_fetch = opts.fetch;	/* The fetch() function */
	this.lom_triggered = false;	/* Did an edge trigger occur? */
	this.lom_pushed = 0;		/* How many items have we pushed? */
	if (opts.hasOwnProperty('fetcharg') === true) {
		this.lom_farg = opts.fetcharg;
	} else {
		this.lom_farg = null;
	}

	if (uoff === true) {
		this.lom_isoff = true;
		this.lom_offset = 0;
	} else if (uoff === false) {
		this.lom_isoff = false;
		this.lom_marker = null;
		this.lom_markfunc = opts.marker;
	} else {
		process.abort();
	}

	/*
	 * By default, use user specified limit. However, if a high water mark
	 * to the stream has been specified, then we'll lower the limit that we
	 * use inherently to account for that so as to minimize memory overhead.
	 * However, we won't do so if that crosses the original limit.
	 */
	this.lom_limit = opts.limit;
	if (opts.hasOwnProperty('streamOptions') &&
	    opts.streamOptions.hasOwnProperty('highWaterMark')) {
		mod_assert.number(opts.streamOptions.highWaterMark);
		if (opts.streamOptions.highWaterMark < opts.limit) {
			this.lom_limit = Math.min(opts.limit,
			    Math.floor(opts.streamOptions.highWaterMark * 2));
			this.lom_limit = Math.max(1, this.lom_limit);
		}
	}

	options = streamOptions(opts.streamOptions,
	    { 'objectMode': true }, { 'highWaterMark': 128 });
	mod_stream.Readable.call(this, options);
	mod_vstream.wrapStream(this);
}

mod_util.inherits(LOMStream, mod_stream.Readable);

/*
 * Valid data objects are those which only have two keys: done and
 * results.
 */
function lomValidData(lomp, data)
{
	var k, i;

	mod_assert.ok(data.hasOwnProperty('results'));
	mod_assert.ok(Array.isArray(data.results));
	mod_assert.bool(data.done);

	if (data.done === false)
		mod_assert.ok(data.results.length > 0 ||
		    lomp.lom_pushed > 0);

	for (k in data) {
		if (!data.hasOwnProperty(k))
			continue;
		for (i = 0; i < LOM_RES_KEYS.length; i++) {
			if (LOM_RES_KEYS[i] === k)
				break;
		}

		mod_assert.ok(i < LOM_RES_KEYS.length,
		    sprintf('unknown result key: %s', k));
	}
}

/*
 * Push a single data object onto the underlying stream. Note, we must update
 * our offset and marker before we push the data, as this may both be the last
 * entry and the user may change things around. We'd rather not keep a copy of a
 * large object in memory if we don't have to, so instead we deal with the cost
 * of potentially excessive marker calculations.
 *
 * In addition, for each data callback we push on, we need to make sure that we
 * reset triggered and increment the number pushed. The latter is mostly for
 * internal sanity checking.
 */
function lomFetchDataCallback(lomp, obj)
{
	mod_assert.object(lomp);
	mod_assert.ok(lomp.lom_finished === false);
	mod_assert.ok(lomp.lom_errored === false);
	mod_assert.ok(lomp.lom_reading === true);

	lomp.lom_pushed++;
	lomp.lom_triggered = false;

	if (lomp.lom_isoff === true) {
		lomp.lom_offset++;
	} else {
		mod_assert.func(lomp.lom_markfunc);
		lomp.lom_marker = lomp.lom_markfunc(obj);
	}

	lomp.push(obj);
}

function lomFetchDoneCallback(lomp, err, data)
{
	var i;

	mod_assert.ok(lomp.lom_reading === true);

	if (err) {
		lomp.emit('error', err);
		lomp.lom_reading = false;
		lomp.lom_finished = true;
		lomp.lom_errored = true;
		lomp.lom_error = err;
		return;
	}

	lomValidData(lomp, data);
	lomp.lom_data = data.results;
	for (i = 0; i < data.results.length; i++) {
		lomFetchDataCallback(lomp, data.results[i]);
	}
	lomp.lom_data = null;
	lomp.lom_reading = false;

	/*
	 * If we're done, then we know that no future read callbacks that we get
	 * matter. As such, we're going to push on now. Here, we don't worry
	 * about turning off reading early because we know that we're not going
	 * to have any more data again, because we're done. We can also skip
	 * anything else that we have to do around updating the marker and
	 * limit.
	 */
	if (data.done === true) {
		lomp.push(null);
		lomp.lom_reading = false;
		lomp.lom_finished = true;
		return;
	}

	/*
	 * We're not done. If node triggered us, we need to respect it's trigger
	 * and call ourselves. Because node is edge-triggered it should not call
	 * us again. If it does, that'd be unfortunate.
	 */
	if (lomp.lom_triggered === true)
		setImmediate(lomInitFetch, lomp);
}

function lomInitFetch(lomp)
{
	var limitObj;
	var dcb = false;

	/*
	 * Reset state
	 */
	lomp.lom_reading = true;
	lomp.lom_pushed = 0;
	lomp.lom_triggered = false;
	limitObj = {};
	limitObj.limit = lomp.lom_limit;
	if (lomp.lom_isoff === true)
		limitObj.offset = lomp.lom_offset;
	else
		limitObj.marker = lomp.lom_marker;
	lomp.lom_fetch(lomp.lom_farg, limitObj, function datacb(obj) {
	        mod_assert.ok(dcb === false);
		lomFetchDataCallback(lomp, obj);
	    }, function donecb(err, res) {
	        mod_assert.ok(dcb === false);
		dcb = true;
		lomFetchDoneCallback(lomp, err, res);
	});
}

LOMStream.prototype._read = function ()
{
	mod_assert.ok(this.lom_finished === false);
	mod_assert.ok(this.lom_errored === false);

	/*
	 * If a read is ongoing, then we don't want to do anything else. This
	 * ensures that we only allow a single outstanding request at any given
	 * time. However, we want to set lom_triggered to true, so that way we
	 * know that we may need to call ourselves again after pushing the last
	 * item onto the queue.
	 */
	if (this.lom_reading === true) {
		mod_assert.ok((this.lom_pushed > 0) ||
		    (this.lom_data !== null && this.lom_data.length > 0));
		this.lom_triggered = true;
		return;
	}

	mod_assert.ok(this.lom_triggered === false);
	lomInitFetch(this);
	return;
};
