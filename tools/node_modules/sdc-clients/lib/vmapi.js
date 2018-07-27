/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2016 Joyent, Inc.
 */

/*
 * Client library for the Triton Virtual Machine API (VMAPI).
 */

var assert = require('assert-plus');
var async = require('async');
var mod_url = require('url');
var restifyClients = require('restify-clients');
var util = require('util');
var format = util.format;

var RestifyClient = require('./restifyclient');



// --- globals

var METADATA_TYPES = ['customer_metadata', 'internal_metadata', 'tags'];



// --- internal support stuff

/*
 * Wait for a job to complete.  Returns an error if the job fails with an error
 * other than the (optional) list of expected errors.
 *
 * TODO: add trace logging
 */
function waitForJob(wfapiUrl, jobUuid, cb) {
    assert.string(wfapiUrl, 'wfapiUrl');
    assert.string(jobUuid, 'jobUuid');
    assert.func(cb, 'cb');

    var client = restifyClients.createJsonClient({url: wfapiUrl, agent: false});
    pollJob(client, jobUuid, function (err, job) {
        if (err)
            return cb(err, job);
        var result = job.chain_results.pop();
        if (result.error) {
            var errmsg = result.error.message || JSON.stringify(result.error);
            return cb(new Error(errmsg), job);
        } else {
            return cb(null, job);
        }
    });
}


/*
 * Poll a job until it reaches either the succeeded or failed state.
 * Taken from SAPI.
 *
 * Note: if a job fails, it's the caller's responsibility to check for a failed
 * job.  The error object will be null even if the job fails.
 */
function pollJob(client, jobUuid, cb) {
    var attempts = 0;
    var errors = 0;

    var timeout = 5000;  // 5 seconds
    var limit = 720;     // 1 hour

    var poll = function () {
        client.get('/jobs/' + jobUuid, function (err, req, res, job) {
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
            } else if (job && job.execution === 'canceled') {
                return cb(null, job);
            } else if (attempts > limit) {
                return cb(new Error('polling for import job timed out'), job);
            }

            return setTimeout(poll, timeout);
        });
    };

    poll();
}



// --- Exported Client

/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function VMAPI(options) {
    RestifyClient.call(this, options);
    this.url = options.url;
}

util.inherits(VMAPI, RestifyClient);


VMAPI.prototype.close = function close() {
    this.client.close();
};


/**
 * Get the workflow API URL on which we can query for job info.
 *
 * Versions of VMAPI after ZAPI-589 will include a 'workflow-api' response
 * header. The fallback is 'http://workflow.$domain' where `$domain` is
 * infered from this VMAPI client's URL. If that is an IP, then we fail.
 *
 */
VMAPI.prototype._getWorkflowApiUrl = function _getWorkflowApiUrl(res) {
    assert.object(res, 'res');
    var vmapiDomainRe = /^vmapi\.(.*?)$/g;

    if (res && res.headers && res.headers['workflow-api']) {
        return res.headers['workflow-api'];
    } else {
        var parsed = mod_url.parse(this.url);
        var match = vmapiDomainRe.exec(parsed.hostname);
        if (match) {
            return format('http://workflow.%s', match[1]);
        } else {
            throw new Error(format(
                'cannot determine Workflow API url from VMAPI url "%s"',
                this.url));
        }
    }
};



// --- endpoint methods

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

    var self = this;
    var reqOpts = { path: '/vms', query: params };
    if (options) {
        reqOpts.headers = options.headers;
        reqOpts.log = options.log || this.log;
    }

    if (params.limit || params.offset) {
        self.get(reqOpts, callback);
    } else {
        listAllVms(callback);
    }

    // This function will execute at least 2 queries when it is not known how
    // the remote VMAPI is returning the collection. If no limit is set, then
    // listVms would receive all VMs on the first call and then perform a second
    // one to discover that all items have been returned. When limit is
    // undefined, listVms will get someVms.length VMs at a time
    function listAllVms(cb) {
        var limit = undefined;
        var offset = params.offset;
        var vms = [];
        var stop = false;

        async.whilst(
            function testAllVmsFetched() {
                return !stop;
            },
            listVms,
            function doneFetching(fetchErr) {
                return cb(fetchErr, vms);
            });

        function listVms(whilstNext) {
            // These options are passed once they are set for the first time
            // or they are passed by the client calling listImages()
            if (offset) {
                params.offset += offset;
            } else {
                params.offset = 0;
            }

            if (limit) {
                params.limit = limit;
            }

            self.get(reqOpts, function (listErr, someVms) {
                if (listErr) {
                    stop = true;
                    return whilstNext(listErr);
                }

                if (!limit) {
                    limit = someVms.length;
                }
                if (!offset) {
                    offset = someVms.length;
                }
                if (someVms.length < limit) {
                    stop = true;
                }

                // We hit this when we either reached an empty page of
                // results or an empty first result
                if (!someVms.length) {
                    stop = true;
                    return whilstNext();
                }

                vms = vms.concat(someVms);
                return whilstNext();
            });
        }
    }
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
 * Gets a VM's /proc by UUID
 *
 * NOTE: Params not documented here as this is experimental.
 */
VMAPI.prototype.getVmProc = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');

    var opts = { path: format('/vms/%s/proc', params.uuid), query: query };
    if (options) {
        opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    return this.get(opts, callback);
};



/**
 * Gets a VM by UUID and/or owner
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Boolean} params.sync: Optional, sync vm data from the CN.
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, vm).
 */
VMAPI.prototype.getVm = function (params, options, callback) {
    var query = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    assert.optionalBool(params.sync, 'params.sync');

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.fields)
        query.fields = params.fields;
    if (params.sync)
        query.sync = 'true';

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
 * @param {Object} params : VM creation parameters.
 * @param {Object} params.context : Optional, value to pass as x-context header
 * @param {String} params.payload : Optional, the VM payload. Otherwise 'params'
 *   is assumed to be the payload.
 * @param {Boolean} params.sync : Optional, if true creation will be synchronous
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.createVm = function (params, options, callback) {
    var query = {};
    var payload;

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');

    /*
     * Additional parameters were required but the existing API had the payload
     * coming in as the first parameter. In order to work around this in a
     * backward-compatible way, we change behavior based on whether 'params'
     * includes a 'payload' member. If it does (the recommended usage going
     * forward) the params other than payload will not be included in the
     * payload. If there is no 'payload' member, we fall back to the old
     * behavior and treat all of params as the payload. In that case we also
     * currently special-case the 'context' member as it was special-cased prior
     * to this 'params' change.
     */
    if (params.payload) {
        if (typeof (params.payload) !== 'object')
            throw new TypeError('param.payload must be an object');

        payload = params.payload;

        if (params.sync) {
            query.sync = 'true';
        }
    } else {
        // the backward-compatible case
        payload = params;
        params = {};
        if (payload.context) {
            params.context = payload.context;
            delete payload.context;
        }
    }

    var opts = {
        path: '/vms',
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    return this.post(opts, payload, callback);
};


VMAPI.prototype.createVmAndWait =
function createVmAndWait(params, options, callback) {
    var self = this;
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    self.createVm(params, options, function (err, jobInfo, res) {
        if (err) {
            callback(err, null, res);
            return;
        }

        var wfapiUrl = self._getWorkflowApiUrl(res);
        assert.string(wfapiUrl, 'wfapiUrl');
        assert.string(jobInfo['job_uuid'], 'job_uuid');
        assert.string(jobInfo['vm_uuid'], 'vm_uuid');

        waitForJob(wfapiUrl, jobInfo['job_uuid'], function (jErr, job) {
            if (jErr) {
                callback(jErr);
                return;
            }
            callback(null, job);
        });
    });
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';
    if (params.timeout)
        query.timeout = params.timeout;
    if (params.idempotent)
        query.idempotent = true;

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    return this.post(opts, {}, callback);
};



/**
 * Sends a signal to a VM. Returns a Job Response Object
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {String} params.signal : Optional, the signal to send to the VM
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job).
 */
VMAPI.prototype.killVm = function (params, options, callback) {
    var query = { action: 'kill' };
    var post_params = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    if (!params || typeof (params) !== 'object')
        throw new TypeError('params is required (object)');
    if (!params.uuid)
        throw new TypeError('UUID is required');
    if ((params.signal) &&
        ['number', 'string'].indexOf(typeof (params.signal)) === -1) {

        throw new TypeError('Signal must be "string" or "number".');
    }
    if (params.owner_uuid)
        query.owner_uuid = params.owner_uuid;
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';
    if (params.idempotent)
        query.idempotent = true;

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    if (params.signal) {
        post_params.signal = params.signal;
    }

    return this.post(opts, post_params, callback);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
 * Adds NICs to a VM and wait for the job to complete.
 *
 * Limitations: VMAPI servers before ZAPI-589 do not include a
 * 'workflow-api' response header. We fallback to trying to infer the
 * Workflow API domain from `this.url`. If that isn't possible, then
 * this will throw an error.
 *
 * @param {Object} params : Filter params.
 * @param {String} params.uuid : the UUID of the VM.
 * @param {String} params.owner_uuid : Optional, the owner of the VM.
 * @param {Array} params.networks : array of network objects (see createVM)
 * @param {Object} options : Request options.
 * @param {Function} callback : of the form f(err, job);
 */
VMAPI.prototype.addNicsAndWait =
function addNicsAndWait(params, options, callback) {
    var self = this;
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    self.addNics(params, options, function (err, jobInfo, res) {
        if (err) {
            callback(err, null, res);
            return;
        }

        var wfapiUrl = self._getWorkflowApiUrl(res);
        assert.string(wfapiUrl, 'wfapiUrl');
        assert.string(jobInfo['job_uuid'], 'job_uuid');
        assert.string(jobInfo['vm_uuid'], 'vm_uuid');

        waitForJob(wfapiUrl, jobInfo['job_uuid'], function (jErr, job) {
            if (jErr) {
                callback(jErr);
                return;
            }
            callback(null, job);
        });
    });
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    var payload = {};

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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';
    if (params.idempotent)
        query.idempotent = true;

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    if (params.update)
        payload.update = params.update;

    return this.post(opts, payload, callback);
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
    var payload = {};

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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';
    if (params.timeout)
        query.timeout = params.timeout;
    if (params.idempotent)
        query.idempotent = true;

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    if (params.update)
        payload.update = params.update;

    return this.post(opts, payload, callback);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/%s', params.uuid, type),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/%s', params.uuid, type),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/%s/%s', params.uuid, type, key),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/%s', params.uuid, type),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;
    if (params.sync)
        query.sync = 'true';

    var opts = {
        path: format('/vms/%s', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/role_tags', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/role_tags', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/role_tags/%s', params.uuid, role_tag),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
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
    if (params.origin)
        query.origin = params.origin;
    if (params.creator_uuid)
        query.creator_uuid = params.creator_uuid;

    var opts = {
        path: format('/vms/%s/role_tags', params.uuid),
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers)
            opts.headers = options.headers;
        opts.log = options.log || this.log;
    }

    if (params.context) {
        opts.headers['x-context'] = JSON.stringify(params.context);
    }

    return this.del(opts, callback);
};


/**
 * Does a ping check to see if API is still serving requests.
 *
 * @param {Function} callback : of the form f(err).
 */


VMAPI.prototype.ping = function (callback) {
    var opts = { path: '/ping' };
    this.get(opts, callback);
};


module.exports = VMAPI;
