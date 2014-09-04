/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * Client library for the SDC Compute Node API (CNAPI)
 */

var util = require('util');
var format = util.format;

var RestifyClient = require('./restifyclient');



// --- Exported Client


/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function CNAPI(options) {
    RestifyClient.call(this, options);
}

util.inherits(CNAPI, RestifyClient);


/**
 * Gets boot params for the given CN
 *
 * @param {String} uuid : CN UUID to get
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.getBootParams = function (uuid, options, callback) {
    if (!uuid)
        throw new TypeError('uuid is required (string)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/boot/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Lists all servers
 *
 * @param {Object} params : Filter params.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.listServers = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: '/servers', query: params };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Gets a server by UUID
 *
 * @param {String} uuid : the UUID of the server.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.getServer = function (uuid, options, callback) {
    if (!uuid)
        throw new TypeError('UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Setup a server by UUID
 *
 * @param {String} uuid : the UUID of the server.
 * @param {Object} params : setup parameters (optional).
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.setupServer = function (uuid, params, options, callback) {
    if (!uuid)
        throw new TypeError('UUID is required');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/setup', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};



/**
 * Gets a task
 *
 * @param {String} id : the task id.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.getTask = function (id, options, callback) {
    if (!id)
        throw new TypeError('Task Id is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/tasks/%s', id) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Creates a vm
 *
 * @param {String} server : the UUID of the server.
 * @param {Object} params : attributes of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.createVm = function (server, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms', server) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Gets a vm on a server
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.getVm = function (server, uuid, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Stops a vm on a server
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.stopVm = function (server, uuid, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s/stop', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, {}, callback);
};



/**
 * Starts a vm on a server
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.startVm = function (server, uuid, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s/start', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, {}, callback);
};



/**
 * Reboots a vm on a server
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.rebootVm = function (server, uuid, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s/reboot', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, {}, callback);
};



/**
 * Update a server
 *
 * @param {String} uuid : server uuid
 * @param {Object} params : Filter params.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.updateServer = function (uuid, params, options, callback) {
    if (!uuid)
        throw new TypeError('UUID is required');
    if (typeof (params) !== 'object')
        throw new TypeError('params must be an object');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Reboot a server
 *
 * @param {String} server : the UUID of the server.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.rebootServer = function (server, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/reboot', server) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, {}, callback);
};



/**
 * Deletes a vm from a server
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.deleteVm = function (server, uuid, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.del(opts, callback);
};



/**
 * Updates nics on a server
 *
 * @param {String} uuid : the UUID of the server.
 * @param {Object} params : Nic params.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.updateNics = function (uuid, params, options, callback) {
    if (!uuid)
        throw new TypeError('UUID is required');
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/nics', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.put(opts, params, callback);
};



/**
 * Runs a command on the specified server.  The optional 'params' argument can
 * contain two fields:
 *
 * @param {Array} args Array containing arguments to be passed in to command
 * @param {Object} env Object containing environment variables to be passed in
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.commandExecute =
function (server, script, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!script)
        throw new TypeError('Script is required');

    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    params.script = script;

    var opts = { path: format('/servers/%s/execute', server) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Ensures an image is installed on a compute node.
 *
 * @param {String} server : the UUID of the server.
 * @param {String} image_uuid : the UUID of the image.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.ensureImage = function (server, image_uuid, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!image_uuid)
        throw new TypeError('Image UUID is required');

    return this.post(format('/servers/%s/ensure-image', server),
        { image_uuid: image_uuid }, callback);
};



/**
 * Returns an object representing the value of a ticket.
 *
 * @param {String} ticketuuid : the UUID of the ticket.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.waitlistTicketGet = function (ticketuuid, callback) {
    var opts = { path: format('/tickets/%s', ticketuuid) };
    this.get(opts, callback);
};



/**
 * Creates a ticket record.
 *
 * @param {String} serveruuid : the UUID of the server on which to create the
 * ticket.
 * @param {Object} ticket : the payload of the ticket.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.waitlistTicketCreate = function (serveruuid, ticket, callback) {
    if (!serveruuid) {
        throw new TypeError('Server UUID is required');
    }

    this.post(format('/servers/%s/tickets', serveruuid),
        ticket, callback);
};



/**
 * Waits for a ticket to go into the 'active' state. Will wait until ticket
 * expires. If ticket expires while waiting a 500 "ticket has expired" error
 * will be returned.
 *
 * @param {String} ticketuuid : the UUID of the ticket.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.waitlistTicketWait = function (ticketuuid, callback) {
    var opts = { path: format('/tickets/%s/wait', ticketuuid) };
    this.get(opts, callback);
};



/**
 * Indicate that a ticket is finished and a new ticket may acquire the
 * resources that were being held.
 *
 * @param {String} ticketuuid : the UUID of the ticket.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.waitlistTicketRelease = function (ticketuuid, callback) {
    var opts = { path: format('/tickets/%s/release', ticketuuid) };
    this.put(opts, {}, callback);
};


/**
 * Get the capacities for a list of servers. If no server UUIDs are provided,
 * return capacities for all servers (more expensive!).
 *
 * @param {Object} serverUuids : List of servers UUIDs to calculate capacity
 * for. For all servers, pass in 'null'.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.capacity = function (serverUuids, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var params = {};
    var opts = { path: '/capacity' };

    if (serverUuids) {
        params.servers = serverUuids;
    }

    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



module.exports = CNAPI;
