/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2017, Joyent, Inc.
 */

/*
 * Client library for the Triton Volume API (VOLAPI).
 */


var assert = require('assert-plus');
var jsprim = require('jsprim');
var util = require('util');

var RestifyClient = require('./restifyclient');

var POLL_VOLUME_STATE_CHANGE_PERIOD_IN_MS = 1000;

function VOLAPI(options) {
    assert.object(options, 'options');
    assert.string(options.userAgent, 'options.userAgent');

    var volapiOpts = jsprim.deepCopy(options);

    volapiOpts.version = '~1';

    RestifyClient.call(this, volapiOpts);
    this.url = volapiOpts.url;
}

util.inherits(VOLAPI, RestifyClient);


VOLAPI.prototype.close = function close() {
    this.client.close();
};

function doCreateVolume(client, params, options, callback) {
    assert.object(client, 'client');
    assert.object(params, 'params');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var opts = {
        path: '/volumes',
        headers: {}
    };

    if (options) {
        if (options.headers) {
            opts.headers = options.headers;
        }

        opts.log = options.log || this.log;
    }

    return client.post(opts, params, callback);
}

VOLAPI.prototype.createVolume =
function createVolume(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    assert.object(params, 'params');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    doCreateVolume(this, params, options, callback);
};

function hrtimeToMs(hrtime) {
    assert.arrayOfNumber(hrtime, 'hrtime');
    assert.ok(hrtime.length === 2, 'hrtime must be an array of length 2');

    var MSECS_PER_SEC = 1000;
    var NSECS_PER_MSEC = 1e6;

    return hrtime[0] * MSECS_PER_SEC + hrtime[1] / NSECS_PER_MSEC;
}

function pollVolumeStateChange(client, volumeUuid, options, callback) {
    assert.object(client, 'client');
    assert.uuid(volumeUuid, 'volumeUuid');
    assert.object(options, 'options');
    assert.arrayOfString(options.successStates, 'options.successStates');
    assert.arrayOfString(options.failureStates, 'options.failureStates');
    assert.optionalNumber(options.timeout, 'options.timeout');
    assert.optionalBool(options.successOnVolumeNotFound,
            'options.successOnVolumeNotFound');
    assert.func(callback, 'callback');

    var pollStart;

    function _poll() {
        client.getVolume({
            uuid: volumeUuid
        }, function onGetVolume(getVolumeErr, volume) {
            var latestPollTimeFromStart = process.hrtime(pollStart);
            var latestPollTimeFromStartInMs =
                hrtimeToMs(latestPollTimeFromStart);

            var volumeInFailState =
                options.failureStates.indexOf(volume.state) !== -1;
            var volumeInSuccessState =
                options.successStates.indexOf(volume.state) !== -1;

            if (getVolumeErr) {
                if (options.successOnVolumeNotFound &&
                    getVolumeErr.statusCode === 404) {
                    callback();
                } else {
                    callback(getVolumeErr, volume);
                }
                return;
            } else if (volumeInFailState) {
                callback(new Error('Volume in state ' + volume.state +
                    ' while polling for states ' +
                    options.successStates.join(', ')));
                return;
            } else if (volumeInSuccessState) {
                callback(null, volume);
            } else {
                if (options.timeout === undefined ||
                    latestPollTimeFromStartInMs < options.timeout) {
                    setTimeout(_poll, POLL_VOLUME_STATE_CHANGE_PERIOD_IN_MS);
                } else {
                    callback(new Error('Timeout when polling for state ' +
                        'change'));
                    return;
                }
            }
        });
    }

    pollStart = process.hrtime();
    setTimeout(_poll, POLL_VOLUME_STATE_CHANGE_PERIOD_IN_MS);
}

function pollVolumeCreation(client, volumeUuid, options, callback) {
    assert.object(client, 'client');
    assert.uuid(volumeUuid, 'volumeUuid');
    assert.object(options, 'options');
    assert.optionalNumber(options.timeout, 'options.timeout');
    assert.func(callback, 'callback');

    pollVolumeStateChange(client, volumeUuid, {
        successStates: ['ready'],
        failureStates: ['failed'],
        timeout: options.timeout
    }, callback);
}

function pollVolumeDeletion(client, volumeUuid, options, callback) {
    assert.object(client, 'client');
    assert.uuid(volumeUuid, 'volumeUuid');
    assert.object(options, 'options');
    assert.optionalNumber(options.timeout, 'options.timeout');
    assert.func(callback, 'callback');

    pollVolumeStateChange(client, volumeUuid, {
        /*
         * Deleted volumes are not kept in the volumes database, so there's no
         * success state to check for. Instead, we consider 404 responses to a
         * GetVolume request to represent a deleted volume.
         */
        successOnVolumeNotFound: true,
        successStates: [],
        failureStates: ['ready', 'failed'],
        timeout: options.timeout
    }, callback);
}

VOLAPI.prototype.createVolumeAndWait =
function createVolumeAndWait(params, options, callback) {
    var createVolOptions = {};

    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    assert.object(params, 'params');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var self = this;

    createVolOptions.headers = options.header;
    createVolOptions.log = options.log;

    doCreateVolume(self, params, createVolOptions,
        function onVolumeCreated(volumeCreationErr, volume) {
            if (volumeCreationErr || volume === undefined ||
                volume.state !== 'creating') {
                callback(volumeCreationErr, volume);
                return;
            } else {
                pollVolumeCreation(self, volume.uuid, {
                    timeout: options.timeout
                }, callback);
            }
        });
};

VOLAPI.prototype.listVolumes = function listVolumes(params, options, callback) {
    // If only one argument then this is 'find all'
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    // If 2 arguments -> (params, callback)
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    assert.optionalObject(params, 'params');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var reqOpts = { path: '/volumes', query: params };
    if (options) {
        reqOpts.headers = options.headers;
        reqOpts.log = options.log || this.log;
    }

    this.get(reqOpts, callback);
};

VOLAPI.prototype.listVolumeSizes =
function listVolumeSizes(params, options, callback) {
    // If only one argument then this is 'find all'
    if (typeof (params) === 'function') {
        callback = params;
        params = {};
    // If 2 arguments -> (params, callback)
    } else if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    assert.optionalObject(params, 'params');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var reqOpts = { path: '/volumesizes', query: params };
    if (options) {
        reqOpts.headers = options.headers;
        reqOpts.log = options.log || this.log;
    }

    this.get(reqOpts, callback);
};

VOLAPI.prototype.getVolume = function getVolume(params, options, callback) {
    var query = {};

    // If 2 arguments -> (params, callback)
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    assert.object(params, 'params');
    assert.uuid(params.uuid, 'params.uuid');
    assert.optionalUuid(params.owner_uuid, 'params.owner_uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    if (params.owner_uuid) {
        query.owner_uuid = params.owner_uuid;
    }

    var reqOpts = { path: '/volumes/' + params.uuid, query: query };
    if (options) {
        reqOpts.headers = options.headers;
        reqOpts.log = options.log || this.log;
    }

    this.get(reqOpts, callback);
};

function doDeleteVolume(client, params, options, callback) {
    var query = {};

    assert.object(client, 'client');
    assert.object(params, 'params');
    assert.uuid(params.uuid, 'params.uuid');
    assert.optionalUuid(params.owner_uuid, 'params.owner_uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    if (params.owner_uuid) {
        query.owner_uuid = params.owner_uuid;
    }

    var reqOpts = {
        path: '/volumes/' + params.uuid,
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers) {
            reqOpts.headers = options.headers;
        }

        reqOpts.log = options.log || this.log;
    }

    return client.del(reqOpts, callback);
}

VOLAPI.prototype.deleteVolume =
function deleteVolume(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = undefined;
    }

    doDeleteVolume(this, params, options, callback);
};

VOLAPI.prototype.deleteVolumeAndWait =
function deleteVolumeAndWait(params, options, callback) {
    var deleteVolOptions = {};

    var self = this;

    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    deleteVolOptions.headers = options.headers;
    deleteVolOptions.log = options.log;

    doDeleteVolume(this, params, options,
        function onVolumeDeleted(volumeDeletionErr, volume) {
            if (volumeDeletionErr || volume === undefined ||
                volume.state !== 'deleting') {
                callback(volumeDeletionErr, volume);
            } else {
                pollVolumeDeletion(self, volume.uuid, {
                    timeout: options.timeout
                }, callback);
            }
        });
};

VOLAPI.prototype.updateVolume =
function updateVolume(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    assert.object(params, 'params');
    assert.uuid(params.uuid, 'params.uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var opts = {
        path: '/volumes/' + params.uuid,
        headers: {}
    };

    if (options) {
        if (options.headers) {
            opts.headers = options.headers;
        }

        opts.log = options.log || this.log;
    }

    return this.post(opts, params, callback);
};

VOLAPI.prototype.createVolumeReservation =
function createVolumeReservation(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    assert.object(params, 'params');
    assert.string(params.volume_name, 'params.volume_name');
    assert.uuid(params.vm_uuid, 'params.vm_uuid');
    assert.uuid(params.job_uuid, 'params.job_uuid');
    assert.uuid(params.owner_uuid, 'params.owner_uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var opts = {
        path: '/volumereservations',
        headers: {}
    };

    if (options) {
        if (options.headers) {
            opts.headers = options.headers;
        }

        opts.log = options.log || this.log;
    }

    return this.post(opts, {
        volume_name: params.volume_name,
        vm_uuid: params.vm_uuid,
        job_uuid: params.job_uuid,
        owner_uuid: params.owner_uuid
    }, callback);
};

VOLAPI.prototype.deleteVolumeReservation =
function deleteVolumeReservation(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    var query = {};

    assert.object(params, 'params');
    assert.string(params.uuid, 'params.uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    if (params.owner_uuid) {
        query.owner_uuid = params.owner_uuid;
    }

    var reqOpts = {
        path: '/volumereservations/' + params.uuid,
        query: query,
        headers: {}
    };

    if (options) {
        if (options.headers) {
            reqOpts.headers = options.headers;
        }

        reqOpts.log = options.log || this.log;
    }

    return this.client.del(reqOpts, callback);
};

VOLAPI.prototype.addVolumeReference =
function addVolumeReference(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    assert.object(params, 'params');
    assert.uuid(params.volume_uuid, 'params.volume_uuid');
    assert.uuid(params.vm_uuid, 'params.vm_uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var opts = {
        path: '/volumes/' + params.volume_uuid + '/addreference',
        headers: {}
    };

    var requestBody = {
        vm_uuid: params.vm_uuid,
        owner_uuid: params.owner_uuid
    };

    if (options) {
        if (options.headers) {
            opts.headers = options.headers;
        }

        opts.log = options.log || this.log;
    }

    return this.post(opts, requestBody, callback);
};

VOLAPI.prototype.removeVolumeReference =
function removeVolumeReference(params, options, callback) {
    if (typeof (options) === 'function') {
        callback = options;
        options = {};
    }

    assert.object(params, 'params');
    assert.uuid(params.volume_uuid, 'params.volume_uuid');
    assert.uuid(params.vm_uuid, 'params.vm_uuid');
    assert.optionalObject(options, 'options');
    assert.func(callback, 'callback');

    var opts = {
        path: '/volumes/' + params.volume_uuid + '/removereference',
        headers: {}
    };

    var requestBody = {
        vm_uuid: params.vm_uuid,
        owner_uuid: params.owner_uuid
    };

    if (options) {
        if (options.headers) {
            opts.headers = options.headers;
        }

        opts.log = options.log || this.log;
    }

    return this.post(opts, requestBody, callback);
};

/**
 * Does a ping check to see if API is still serving requests.
 *
 * @param {Function} callback : of the form f(err).
 */
VOLAPI.prototype.ping = function (callback) {
    var opts = { path: '/ping' };
    this.get(opts, callback);
};

module.exports = VOLAPI;
