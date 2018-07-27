/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2015, Joyent, Inc.
 */

/*
 * Client library for the SDC Firewall API (FWAPI)
 */

var assert = require('assert-plus');
var RestifyClient = require('./restifyclient');
var util = require('util');
var format = util.format;



// --- Exported Client



/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function FWAPI(options) {
    RestifyClient.call(this, options);
}

util.inherits(FWAPI, RestifyClient);



// --- Misc methods



/**
 * Ping FWAPI server.
 *
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.ping = function (params, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = undefined;
    }

    return this.get('/ping', params, callback);
};



// --- Rule methods



/**
 * Lists all rules.
 *
 * @param {Function} params : Parameters (optional).
 * @param {Object} options : Request options (optional).
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.listRules = function (params, options, callback) {
    // If only one argument then this is 'find all'
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    // If 2 arguments -> (params, callback)
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/rules' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, params, callback);
};


/**
 * Gets a rule by UUID.
 *
 * @param {String} uuid : the rule UUID.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.getRule = function (uuid, params, callback) {
    assert.string(uuid, 'uuid');
    return this.get(format('/rules/%s', uuid), params, callback);
};


/**
 * Updates the rule specified by uuid.
 *
 * @param {String} uuid : the rule UUID.
 * @param {Object} params : the parameters to update.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.updateRule = function (uuid, params, callback) {
    assert.string(uuid, 'uuid');
    assert.object(params, 'params');
    return this.put(format('/rules/%s', uuid), params, callback);
};


/**
 * Creates a rule.
 *
 * @param {Object} params : the rule parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.createRule = function (params, options, callback) {
    assert.object(params, 'params');

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/rules' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Deletes the rule specified by uuid.
 *
 * @param {String} uuid : the rule UUID.
 * @param {Object} params : optional parameters.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.deleteRule = function (uuid, params, callback) {
    assert.string(uuid, 'uuid');
    return this.del(format('/rules/%s', uuid), params, callback);
};


/**
 * Gets VMs affected by a rule.
 *
 * @param {String} uuid : the rule UUID.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.getRuleVMs = function (uuid, params, callback) {
    assert.string(uuid, 'uuid');
    return this.get(format('/rules/%s/vms', uuid), params, callback);
};


/**
 * Gets rules affecting a VM.
 *
 * @param {String} uuid : the rule UUID.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.getVMrules = function (uuid, params, callback) {
    assert.string(uuid, 'uuid');
    return this.get(format('/firewalls/vms/%s', uuid), params, callback);
};



// --- Update methods


/**
 * Creates an update.
 *
 * @param {Object} params : the update parameters.
 * @param {Function} callback : of the form f(err, res).
 */
FWAPI.prototype.createUpdate = function (params, callback) {
    assert.object(params, 'params');
    return this.post('/updates', params, callback);
};


module.exports = FWAPI;
