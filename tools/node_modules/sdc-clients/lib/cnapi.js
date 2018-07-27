/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2016 Joyent, Inc.
 */

/*
 * Client library for the SDC Compute Node API (CNAPI)
 */

var util = require('util');
var format = util.format;
var assert = require('assert-plus');
var restifyClients = require('restify-clients');
var RestifyClient = require('./restifyclient');


/*
 * Poll a job until it reaches either the succeeded or failed state.
 * Taken from SAPI.
 *
 * Note: if a job fails, it's the caller's responsibility to check for a failed
 * job.  The error object will be null even if the job fails.
 */
function pollJob(client, job_uuid, cb) {
    var attempts = 0;
    var errors = 0;

    var timeout = 5000;  // 5 seconds
    var limit = 720;     // 1 hour

    var poll = function () {
        client.get('/jobs/' + job_uuid, function (err, req, res, job) {
            attempts++;

            if (err) {
                errors++;
                if (errors >= 5) {
                    return cb(err);
                } else {
                    return setTimeout(poll, timeout);
                }
            }

            if (job && job.execution === 'succeeded') {
                return cb(null, job);
            } else if (job && job.execution === 'failed') {
                return cb(null, job);
            } else if (attempts > limit) {
                return cb(new Error('polling for import job timed out'), job);
            }

            return setTimeout(poll, timeout);
        });
    };

    poll();
}


/*
 * Wait for a job to complete.  Returns an error if the job fails with an error
 * other than the (optional) list of expected errors. Taken from SAPI
 */
function waitForJob(url, job_uuid, cb) {
    assert.string(url, 'url');
    assert.string(job_uuid, 'job_uuid');
    assert.func(cb, 'cb');

    var client = restifyClients.createJsonClient({url: url, agent: false});
    pollJob(client, job_uuid, function (err, job) {
        if (err) {
            return cb(err);
        }
        var result = job.chain_results.pop();
        if (result.error) {
            var errmsg = result.error.message || JSON.stringify(result.error);
            return cb(new Error(errmsg));
        } else {
            return cb();
        }
    });
}

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
 * Exec sysinfo into the given CN and wait for the job to complete
 *
 * @param {String} uuid: CN UUID to run sysinfo-refresh
 * @param {Object} options: Request options.
 * @param {String} wf_api_url: Workflow API url
 * @param {Function} cb: callback of the form f(err)
 */
CNAPI.prototype.refreshSysinfoAndWait =
function (uuid,  wf_api_url, options, cb) {
    if (!uuid) {
        throw new TypeError('uuid is required (string)');
    }

    if (!wf_api_url) {
        throw new TypeError('wf_api_url is required (string)');
    }

    if (typeof (options) === 'function') {
        cb = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/sysinfo-refresh', uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, {}, function (err, res) {
        if (err) {
            return cb(err);
        }

        // Pre CNAPI-529
        if (!res.job_uuid) {
            return cb();
        }

        return waitForJob(wf_api_url, res.job_uuid, function (jErr, job) {
            if (jErr) {
                return cb(jErr);
            }
            return cb(null, job);
        });
    });
};

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
 * Sets boot params for the given CN
 *
 * @param {String} uuid : CN UUID to set
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.setBootParams = function (uuid, params, options, callback) {
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

    return this.post(opts, params, callback);
};


/**
 * Lists all servers.
 *
 * By default this will page through results to list all servers. If
 * `params.limit` and/or `params.offset` is provided, then paging is *not*
 * done. I.e. it is assume the caller is attempting to manually do so.
 *
 * Supported call signature styles:
 *      cnapi.listServers(function (err, servers) { ... });
 *      cnapi.listServers(FILTER-PARAMS, function (err, servers) { ... });
 *      cnapi.listServers(FILTER-PARAMS, REQ-OPTIONS,
 *          function (err, servers) { ... });
 *
 * @param {Object} params - Query params to CNAPI's ListServers endpoint.
 * @param {Object} options - Optional. Extra request options.
 *      - {Object} options.log - Bunyan logger. If not given the CNAPI client's
 *        `log` is used.
 *      - {Object} options.headers
 * @param {Function} callback - `function (err, servers)`.
 */
CNAPI.prototype.listServers = function (params, options, callback) {
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var self = this;
    var reqOpts = { path: '/servers', query: params };
    if (options) {
        reqOpts.headers = options.headers;
        reqOpts.log = options.log || this.log;
    }

    if (params.hasOwnProperty('limit') || params.hasOwnProperty('offset')) {
        self.get(reqOpts, callback);
    } else {
        listAllServers(callback);
    }

    /*
     * CNAPI ServerList promises a default and max limit of 1000, so we'll use
     * that. If we get <1000 servers on a request, then we are done.
     */
    function listAllServers(next) {
        var limit = 1000;
        var offset = 0;
        var allServers = [];
        var firstReq;
        var firstRes;

        var listPageOfServers = function () {
            if (limit !== null) {
                reqOpts.query.limit = limit;
            }
            reqOpts.query.offset = offset;

            self.get(reqOpts, function (err, servers, req, res) {
                if (err) {
                    next(err, null, req, res);
                    return;
                }

                if (!firstReq) {
                    firstReq = req;
                    firstRes = res;
                }

                allServers = allServers.concat(servers);

                if (servers.length < limit) { // Done paging.
                    // For backwards compat, we return the *first* req/res.
                    next(null, allServers, firstReq, firstRes);
                } else {
                    // Need to fetch another page of servers.
                    offset += servers.length;
                    listPageOfServers();
                }
            });
        };

        listPageOfServers();
    }
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
 * Wait for a task to complete or a timeout to be fired.
 *
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, task).
 */

CNAPI.prototype.waitTask = function (id, options, callback) {

    if (!id) {
        throw new TypeError('task id is required');
    }

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/tasks/%s/wait', id) };

    if (options.timeout) {
        opts.path = format('%s?timeout=%d', opts.path, options.timeout);
    }

    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.get(opts, callback);
};



/**
 * Periodically check if a task has completed.
 *
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, task).
 */

CNAPI.prototype.pollTask = function (id, options, callback) {
    var self = this;

    if (!id) {
        throw new TypeError('task id is required');
    }

    // Repeat checkTask until task has finished
    checkTask();

    function checkTask() {
        self.getTask(id, options, onGetTask);

        function onGetTask(err, task) {
            if (err) {
                callback(err);
            } else if (task.status === 'failure') {
                callback(new Error('task failed'), task);
            } else if (task.status === 'complete') {
                callback(null, task);
            } else {
                setTimeout(checkTask, 1000);
            }
        }
    }
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
 * @param {Function} callback : of the form f(err, body, res).
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
 * @param {String} params : the Image parameters.
 * @param {Function} callback : of the form f(err, res).
 */

CNAPI.prototype.ensureImage = function (server, params, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!params)
        throw new TypeError('Image params is required');

    // Fallback to support old style image_uuid as second parameter
    if (typeof (params) === 'string') {
        params = { image_uuid: params };
    }

    return this.post(format('/servers/%s/ensure-image', server),
        params, callback);
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


/**
 * Returns all actively installed platforms.
 *
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */


CNAPI.prototype.listPlatforms = function (options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }
    var opts = { path: '/platforms' };
    if (options && options.headers) {
        opts.headers = options.headers;
    }
    this.get(opts, callback);
};



/**
 * Queues a command execution on a docker VM
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.dockerExec =
function (server, uuid, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (!params)
        throw new TypeError('Params is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s/docker-exec', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Requests given server instantiate a tcp service with the intent of streaming
 * the contents of a file within a docker VM.
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.dockerCopy =
function (server, uuid, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (!params)
        throw new TypeError('Params is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var opts = { path: format('/servers/%s/vms/%s/docker-copy', server, uuid) };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Requests given server instantiate a tcp service with the intent of streaming
 * back json stat events for the given docker VM.
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.dockerStats =
function (server, uuid, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (!params)
        throw new TypeError('Params is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var path = format('/servers/%s/vms/%s/docker-stats', server, uuid);
    var opts = { path: path };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Requests given server instantiate a tcp service with the intent of streaming
 * the build context (tar stream) and passing back newline separated json
 * events.
 *
 * @param {String} server : the UUID of the server.
 * @param {String} uuid : the UUID of the vm.
 * @param {Object} params : Build params as send from the docker client.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, res).
 */
CNAPI.prototype.dockerBuild =
function (server, uuid, params, options, callback) {
    if (!server)
        throw new TypeError('Server UUID is required');
    if (!uuid)
        throw new TypeError('VM UUID is required');
    if (!params)
        throw new TypeError('Params is required');
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    var path = format('/servers/%s/vms/%s/docker-build', server, uuid);
    var opts = { path: path };
    if (options && options.headers) {
        opts.headers = options.headers;
    }

    return this.post(opts, params, callback);
};



/**
 * Does a ping check to see if API is still serving requests.
 *
 * @param {Function} callback : of the form f(err).
 */


CNAPI.prototype.ping = function (callback) {
    var opts = { path: '/ping' };
    this.get(opts, callback);
};



module.exports = CNAPI;
