/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2016, Joyent, Inc.
 */

module.exports = CNS;

var assert = require('assert-plus');
var util = require('util');
var format = util.format;
var RestifyClient = require('./restifyclient');

/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function CNS(options) {
    RestifyClient.call(this, options);
}
util.inherits(CNS, RestifyClient);

/**
 * Ping the CNS REST server.
 *
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err)
 */
CNS.prototype.ping = function (options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: '/ping' };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Retrieves the information that CNS has recorded about a given SDC VM,
 * including the DNS records associated with it (both instance and service
 * records)
 *
 * @param {String} uuid: the VM's UUID
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, obj)
 */
CNS.prototype.getVM = function (uuid, options, callback) {
    assert.uuid(uuid, 'uuid');
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: format('/vm/%s', uuid) };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Lists all the peers of the CNS server (secondary nameservers that have
 * used zone transfers to replicate its contents)
 *
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, objs)
 */
CNS.prototype.listPeers = function (options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: '/peers' };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Gets detailed information (beyond the information included in ListPeers)
 * about a particular peer.
 *
 * @param {String} address: the peer's address
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, obj)
 */
CNS.prototype.getPeer = function (address, options, callback) {
    assert.string(address, 'address');
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: format('/peer/%s', address) };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Deletes a peer from CNS, causing all state about the peer (including
 * knowledge about its latest sync'd serial numbers, whether it supports
 * NOTIFY etc) to be forgotten.
 *
 * @param {String} address: the peer's address
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err)
 */
CNS.prototype.deletePeer = function (address, options, callback) {
    assert.string(address, 'address');
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: format('/peer/%s', address) };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.del(opts, callback);
};

/**
 * Lists all zones served by the CNS server and their latest generated
 * serial numbers.
 *
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, objs)
 */
CNS.prototype.listZones = function (options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: '/zones' };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Lists the current contents of the peer ACL. Addresses that match an entry
 * in this ACL will be allowed to perform a zone transfer and become a new
 * peer.
 *
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, objs)
 */
CNS.prototype.listAllowedPeers = function (options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: '/allowed-peers' };
    if (options.headers) {
        opts.headers = options.headers;
    }
    return this.get(opts, callback);
};

/**
 * Calculates the DNS search suffixes that should be used for a new VM, based
 * on the VM's proposed owner and networks it will be connected to.
 *
 * The ordering of the suffixes will prefer CNS "service" records over
 * "instance" records.
 *
 * @param {String} owner : UUID of the proposed owner of the new VM
 * @param {Array(String)} networks : UUIDs of networks the new VM will use
 * @param {Object} options : any extra options for this request
 * @param {Function} callback : of the form f(err, suffixes)
 */
CNS.prototype.getSuffixesForVM = function (owner, networks, options, callback) {
    assert.string(owner, 'owner UUID');
    assert.arrayOfString(networks, 'network UUIDs');
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }
    var opts = { path: '/suffixes-for-vm' };
    if (options.headers) {
        opts.headers = options.headers;
    }
    var params = {
        networks: networks,
        owner_uuid: owner
    };
    return this.post(opts, params, callback);
};
