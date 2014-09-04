/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * Client library for the SDC Networking API (NAPI)
 */

var assert = require('assert-plus');
var util = require('util');
var format = util.format;
var RestifyClient = require('./restifyclient');



// --- Exported Client



/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function NAPI(options) {
    RestifyClient.call(this, options);
}

util.inherits(NAPI, RestifyClient);


/**
 * Ping NAPI server.
 *
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.ping = function (callback) {
    return this.get('/ping', callback);
};



// --- Network pool methods



/**
 * Creates a Network Pool
 *
 * @param {String} name: the name.
 * @param {Object} params : the pool parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.createNetworkPool = function (name, params, options, callback) {
    assert.string(name, 'name');
    assert.object(params, 'params');
    params.name = name;

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/network_pools' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Deletes the Network Pool specified by UUID.
 *
 * @param {String} uuid : the UUID.
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.deleteNetworkPool = function (uuid, params, options, callback) {
    assert.string(uuid, 'uuid');

    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/network_pools/%s', uuid), query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};


/**
 * Gets a Network Pool by UUID
 *
 * @param {String} uuid : the UUID.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getNetworkPool = function (uuid, options, callback) {
    assert.string(uuid, 'uuid');

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/network_pools/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    if (options && options.params) {
        opts.query = options.params;
    }

    return this.get(opts, callback);
};


/**
 * Lists all Network Pools
 *
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listNetworkPools = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/network_pools', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Updates the Network Pool specified by UUID.
 *
 * @param {String} uuid : the UUID.
 * @param {Object} params : the parameters to update.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateNetworkPool = function (uuid, params, options, callback) {
    assert.string(uuid, 'uuid');

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/network_pools/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};



// --- Nic methods



/**
 * Lists all Nics
 *
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listNics = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/nics', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Gets a Nic by MAC address.
 *
 * @param {String} macAddr : the MAC address.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getNic = function (macAddr, options, callback) {
    if (!macAddr)
        throw new TypeError('macAddr is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/nics/%s', macAddr.replace(/:/g, '')) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Updates the Nic specified by MAC address.
 *
 * @param {String} macAddr : the MAC address.
 * @param {Object} params : the parameters to update.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateNic = function (macAddr, params, options, callback) {
    if (!macAddr)
        throw new TypeError('macAddr is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/nics/%s', macAddr.replace(/:/g, '')) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};


/**
 * Gets the nics for the given owner
 *
 * @param {String} belongsTo : the UUID that the nics belong to
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getNics = function (belongsTo, options, callback) {
    if (!belongsTo)
        throw new TypeError('belongsTo is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (options === undefined) {
        this.listNics({ belongs_to_uuid: belongsTo }, callback);
    } else {
        this.listNics({ belongs_to_uuid: belongsTo }, options, callback);
    }
    return;
};


/**
 * Creates a Nic
 *
 * @param {String} macAddr : the MAC address.
 * @param {Object} params : the nic parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.createNic = function (macAddr, params, options, callback) {
    if (!macAddr)
        throw new TypeError('macAddr is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    params.mac = macAddr;

    var opts = { path: '/nics' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Provisions a new Nic, with an IP address on the given logical network
 *
 * @param {String} network : the logical network to create this nic on
 * @param {Object} params : the nic parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.provisionNic = function (network, params, options, callback) {
    if (!network)
        throw new TypeError('network is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s/nics', network) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Deletes the Nic specified by MAC address.
 *
 * @param {String} macAddr : the MAC address.
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.deleteNic = function (macAddr, params, options, callback) {
    if (!macAddr)
        throw new TypeError('macAddr is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = {
        path: format('/nics/%s', macAddr.replace(/:/g, '')),
        query: params
    };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};



// --- Network methods



/**
 * Lists all Networks
 *
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listNetworks = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/networks', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Creates a Network
 *
 * @param {Object} params : the network parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.createNetwork = function (params, options, callback) {
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/networks' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Gets a Network by UUID.
 *
 * @param {String} uuid : the UUID.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getNetwork = function (uuid, options, callback) {
    if (!uuid)
        throw new TypeError('uuid is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    if (options && options.params) {
        opts.query = options.params;
    }

    return this.get(opts, callback);
};


/**
 * Updates the Network specified by UUID.
 *
 * @param {String} uuid : the UUID.
 * @param {Object} params : the parameters to update.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateNetwork = function (uuid, params, options, callback) {
    assert.string(uuid, 'uuid');

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};


/**
 * Deletes a Network by UUID.
 *
 * @param {String} uuid : the UUID.
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.deleteNetwork = function (uuid, params, options, callback) {
    if (!uuid)
        throw new TypeError('uuid is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s', uuid), query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};


/**
 * Lists the IPs for the given logical network
 *
 * @param {String} network : the logical network to list IPs on
 * @param {Object} params : the parameters to pass
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listIPs = function (network, params, options, callback) {
    if (!network)
        throw new TypeError('network is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s/ips', network), query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Gets an IP on the given logical network
 *
 * @param {String} network : the logical network that the IP is on
 * @param {String} ipAddr : the IP address to get info for
 * @param {Object} params : the parameters to pass
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getIP = function (network, ipAddr, params, options, callback) {
    if (!network)
        throw new TypeError('network is required (string)');
    if (!ipAddr)
        throw new TypeError('ip address is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = {
        path: format('/networks/%s/ips/%s', network, ipAddr),
        query: params
    };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Updates an IP on the given logical network
 *
 * @param {String} network : the logical network the IP is on
 * @param {String} ipAddr : the address of the IP to update
 * @param {Object} params : the parameters to update
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateIP =
function (network, ipAddr, params, options, callback) {
    if (!network)
        throw new TypeError('network is required (string)');
    if (!ipAddr)
        throw new TypeError('ip address is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/networks/%s/ips/%s', network, ipAddr) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};


/**
 * Searches for an IP by address
 *
 * @param {String} ipAddr : the IP address to search for
 * @param {Object} params : the parameters to pass
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.searchIPs = function (ipAddr, params, options, callback) {
    if (!ipAddr)
        throw new TypeError('ip address is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    params.ip = ipAddr;
    var opts = { path: '/search/ips', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



// --- Nic Tag methods



/**
 * Lists all Nic Tags
 *
 * @param {Object} params : the parameters to pass
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listNicTags = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/nic_tags', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Creates a Nic Tag
 *
 * @param {String} name : the name of the nic tag.
 * @param {Object} params : the parameters to create the tag with (optional).
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.createNicTag = function (name, params, options, callback) {
    if (!name)
        throw new TypeError('name is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    params.name = name;
    var opts = { path: '/nic_tags' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Gets a Nic tag
 *
 * @param {String} name : the name of the nic tag.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getNicTag = function (name, options, callback) {
    if (!name)
        throw new TypeError('name is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/nic_tags/%s', name) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Updates the Nic tag
 *
 * @param {String} name : the name of the nic tag.
 * @param {Object} params : the parameters to update.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateNicTag = function (name, params, options, callback) {
    if (!name)
        throw new TypeError('name is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/nic_tags/%s', name) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};


/**
 * Deletes the Nic tag
 *
 * @param {String} name : the name of the nic tag.
 * @param {Object} params : the optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.deleteNicTag = function (name, params, options, callback) {
    if (!name)
        throw new TypeError('name is required (string)');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/nic_tags/%s', name), query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};



// --- Aggregation methods



/**
 * Lists all Aggregations
 *
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.listAggrs = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/aggregations', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Creates an Aggregation
 *
 * @param {Object} params : the aggregation parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.createAggr = function (params, options, callback) {
    assert.object(params, 'params');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/aggregations' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};


/**
 * Gets an Aggregation by ID.
 *
 * @param {String} id : the ID.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.getAggr = function (id, options, callback) {
    assert.string(id, 'id');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/aggregations/%s', id) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};


/**
 * Updates the Aggregation specified by ID.
 *
 * @param {String} id : the ID.
 * @param {Object} params : the parameters to update.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.updateAggr = function (id, params, options, callback) {
    assert.string(id, 'id');
    assert.object(params, 'params');

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/aggregations/%s', id) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};


/**
 * Deletes an Aggregation by ID.
 *
 * @param {String} id : the ID.
 * @param {Object} params : optional parameters.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
NAPI.prototype.deleteAggr = function (id, params, options, callback) {
    assert.string(id, 'id');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/aggregations/%s', id), query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};

module.exports = NAPI;
