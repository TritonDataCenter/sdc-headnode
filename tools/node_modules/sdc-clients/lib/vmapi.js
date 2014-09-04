/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * Client library for the SDC Networking API (VMAPI)
 */

var util = require('util');
var format = util.format;

var RestifyClient = require('./restifyclient');
var METADATA_TYPES = ['customer_metadata', 'internal_metadata', 'tags'];


// --- Exported Client


/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function VMAPI(options) {
    RestifyClient.call(this, options);
}

util.inherits(VMAPI, RestifyClient);


VMAPI.prototype.close = function close() {
    this.client.close();
};

// --- Vm methods



/**
 * Lists all VMs
 *
 * @param {Object} params : Filter params.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, vms).
 */
VMAPI.prototype.listVms = function (params, options, callback) {
    // If only one argument then this is 'find all'
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    // If 2 arguments -> (params, callback)
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/vms', query: params };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Count VMs
 *
 * @param {Object} params : Filter params.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, counter).
 */
VMAPI.prototype.countVms = function countVms(params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/vms', query: params };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.client.head(opts, function (err, req, res) {
        if (err) {
            return callback(err);
        }
        return callback(null,
            (Number(res.headers['x-joyent-resource-count']) || 0));
    });
};


/**
 * Gets a VM by UUID and/or owner
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, vm).
 */
VMAPI.prototype.getVm = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.fields)
        query.fields = params.fields;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Creates a VM. Returns a Job Response Object
 *
 * @param {Object} body : attributes of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.createVm = function (body, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!body || typeof (body) !== 'object')
        throw new TypeError('body is required (object)');

    var opts = { path: '/vms' };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, body, callback);
};



/**
 * Stops a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.stopVm = function (params, options, callback) {
    var query = { action: 'stop' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};


/**
 * Adds NICs to a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Array} params.networks : array of network objects (see createVM)
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.addNics = function (params, options, callback) {
    var query = { action: 'add_nics' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!Array.isArray(params.networks) && !Array.isArray(params.macs))
        throw new TypeError('networks or macs are required (array)');
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    var args;
    if (params.networks) {
        args = { networks: params.networks };
    } else {
        args = { macs: params.macs };
    }

    return this.post(opts, args, callback);
};


/**
 * Updates NICs on a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Array} params.nics : array of NIC objects
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.updateNics = function (params, options, callback) {
    var query = { action: 'update_nics' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!Array.isArray(params.nics))
        throw new TypeError('nics is required (array)');
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, { nics: params.nics }, callback);
};


/**
 * Remove NICs from a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Array} params.macs : array of mac addresses of nics to remove
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.removeNics = function (params, options, callback) {
    var query = { action: 'remove_nics' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (! Array.isArray(params.macs))
        throw new TypeError('macs is required (array)');
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, { macs: params.macs }, callback);
};




/**
 * Starts a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.startVm = function (params, options, callback) {
    var query = { action: 'start' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};



/**
 * Reboots a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.rebootVm = function (params, options, callback) {
    var query = { action: 'reboot' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};



/**
 * Reprovisions a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {String} params.image_uuid : the UUID of the Image to reprovision
 *   the VM with
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.reprovisionVm = function (params, options, callback) {
    var query = { action: 'reprovision' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.image_uuid)
        throw new TypeError('Image UUID (image_uuid) is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, { image_uuid: params.image_uuid }, callback);
};



/**
 * Updates a VM. Returns a Job Response Object
 *
 * TODO: need to fix this so params and update body are separate
 *
 * @param {Object} params : Filter/update params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {String} params.payload : VM attributes to be updated.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 *
 * TODO: fix it so actual zone attrs != params
 */
VMAPI.prototype.updateVm = function (params, options, callback) {
    var query = { action: 'update' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.payload || typeof (params.payload) !== 'object')
        throw new TypeError('params.payload is required (object)');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, params.payload, callback);
};



/**
 * Destroys a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter/update params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteVm = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.del(opts, callback);
};



/**
 * Lists metadata for a VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *        'internal_metadata' or 'tags'.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, metadata).
 */
VMAPI.prototype.listMetadata = function (type, params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;

    var opts = { path: format('/vms/%s/%s', params.uuid, type), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Gets the metadata value for a key on the given VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *        'internal_metadata' or 'tags'.
 * @param {String} key : Metadata key.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, metadata).
 */
VMAPI.prototype.getMetadata = function (type, key, params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!key || typeof (key) !== 'string')
        throw new TypeError('key is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;

    var opts = {
        path: format('/vms/%s/%s/%s', params.uuid, type, key),
        query: query
    };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Adds (appends) metadata to a VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *      'internal_metadata' or 'tags'.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} params.metadata : Metadata to be added to the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 *
 * TODO: fix it so actual metadata != params
 */
VMAPI.prototype.addMetadata = function (type, params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.metadata || typeof (params.metadata) !== 'object')
        throw new TypeError('params.metadata is required (object)');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/%s', params.uuid, type), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, params.metadata, callback);
};



/**
 * Sets (replaces) new metadata for a VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *      'internal_metadata' or 'tags'.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} params.metadata : Metadata to be set for the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 *
 * TODO: fix it so actual metadata != params
 */
VMAPI.prototype.setMetadata = function (type, params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.metadata || typeof (params.metadata) !== 'object')
        throw new TypeError('params.metadata is required (object)');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/%s', params.uuid, type), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.put(opts, params.metadata, callback);
};



/**
 * Deletes a metadata key from a VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *      'internal_metadata' or 'tags'.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} key : Metadata key to be deleted.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteMetadata =
function (type, params, key, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!key)
        throw new TypeError('Metadata \'key\' is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/%s/%s', params.uuid, type, key),
        query: query
    };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.del(opts, callback);
};



/**
 * Deletes ALL metadata from a VM
 *
 * @param {String} type : the metadata type, can be 'customer_metadata',
 *      'internal_metadata' or 'tags'.
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteAllMetadata = function (type, params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!type || typeof (type) !== 'string' ||
        (METADATA_TYPES.indexOf(type) == -1))
        throw new TypeError('type is required (string)');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/%s', params.uuid, type), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.del(opts, callback);
};


/**
 * Creates a VM snapshot. Returns a Job Response Object
 *
 * @param {String} uuid : the UUID of the VM. (Required)
 * @param {String} owner_uuid : the UUID of the VM owner. (Optional)
 * @param {String} name: Snapshot name. (YYYYMMDDTHHMMSSZ if not given)
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.snapshotVm = function (params, options, callback) {
    var query = { action: 'create_snapshot' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.name)
        query.snapshot_name = params.name;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};


/**
 * Rolls back a VM to a snapshot. Returns a Job Response Object
 *
 * @param {String} uuid : the UUID of the VM. (Required)
 * @param {String} owner_uuid : the UUID of the VM owner. (Optional)
 * @param {String} name: Snapshot name. (YYYYMMDDTHHMMSSZ if not given)
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.rollbackVm = function (params, options, callback) {
    var query = { action: 'rollback_snapshot' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (!params.name) {
        throw new TypeError('Snapshot name is required');
    } else {
        query.snapshot_name = params.name;
    }
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};


/**
 * Rolls back a VM to a snapshot. Returns a Job Response Object
 *
 * @param {String} uuid : the UUID of the VM. (Required)
 * @param {String} owner_uuid : the UUID of the VM owner. (Optional)
 * @param {String} name: Snapshot name. (YYYYMMDDTHHMMSSZ if not given)
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteSnapshot = function (params, options, callback) {
    var query = { action: 'delete_snapshot' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (!params.name) {
        throw new TypeError('Snapshot name is required');
    } else {
        query.snapshot_name = params.name;
    }
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, {}, callback);
};


/**
 * Lists all Jobs
 *
 * @param {Object} params : Filter params.
 * @param {String} params.task : the job task type.
 * @param {String} params.vm_uuid : the UUID of the VM.
 * @param {String} params.execution : the job execution state.
 * @param {Function} callback : of the form f(err, jobs).
 */
VMAPI.prototype.listJobs = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/jobs', query: params };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Gets a Job by UUID
 *
 * @param {String} uuid : the UUID of the Job.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.getJob = function (uuid, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!uuid)
        throw new TypeError('UUID is required');

    var opts = { path: format('/jobs/%s', uuid) };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



// VM Role Tags

/**
 * Lists role tags for a VM
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, metadata).
 */
VMAPI.prototype.listRoleTags = function (params, options, callback) {
    var query = { fields: 'role_tags' };

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;

    var opts = { path: format('/vms/%s', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, function (err, vm, req, res) {
        if (err) {
            return callback(err);
        }
        return callback(null, vm.role_tags);
    });
};


/**
 * Adds (appends) role_tags to a VM
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} params.role_tags : Role tags to be added to the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 *
 */
VMAPI.prototype.addRoleTags = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.role_tags || typeof (params.role_tags) !== 'object')
        throw new TypeError('params.role_tags is required (object)');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/role_tags', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.post(opts, { role_tags: params.role_tags }, callback);
};



/**
 * Sets (replaces) new role_tags for a VM
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} params.role_tags : Role tags to be set for the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.setRoleTags = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!params.role_tags || typeof (params.role_tags) !== 'object')
        throw new TypeError('params.role_tags is required (object)');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/role_tags', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.put(opts, { role_tags: params.role_tags }, callback);
};



/**
 * Deletes a role tag from a VM
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} key : Metadata key to be deleted.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteRoleTag = function (params, role_tag, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (!role_tag)
        throw new TypeError('Role tag is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/role_tags/%s', params.uuid, role_tag),
        query: query
    };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.del(opts, callback);
};



/**
 * Deletes ALL role tags from a VM
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.deleteAllRoleTags = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.context)
        query.context = params.context;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = { path: format('/vms/%s/role_tags', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.del(opts, callback);
};


module.exports = VMAPI;
