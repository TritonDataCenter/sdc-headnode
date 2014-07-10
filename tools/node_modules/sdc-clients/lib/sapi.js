/*
 * Copyright (c) 2013, Joyent, Inc. All rights reserved.
 *
 * lib/sapi.js: client library for the SDC Services API (SAPI)
 */

var assert = require('assert-plus');
var async = require('async');
var fs = require('fs');
var qs = require('querystring');
var path = require('path');
var util = require('util');
var vasync = require('vasync');

var sprintf = require('util').format;

var RestifyClient = require('./restifyclient');



// --- API Functions


/**
 * Constructor
 *
 * See the RestifyClient constructor for details
 */
function SAPI(options) {
    assert.object(options, 'options');
    assert.object(options.log, 'options.log');

    this.log = options.log;

    RestifyClient.call(this, options);
}

util.inherits(SAPI, RestifyClient);


SAPI.prototype.close = function close() {
    if (this.client)
        this.client.close();
};


// --- Applications

/**
 * Create an application
 *
 * @param {Function} callback: of the form f(err, app).
 */
function createApplication(name, owner_uuid, opts, callback) {
    assert.string(name, 'name');
    assert.string(owner_uuid, 'owner_uuid');

    if (typeof (opts) === 'function') {
        callback = opts;
        opts = {};
    }

    opts.name = name;
    opts.owner_uuid = owner_uuid;

    return (this.post('/applications', opts, callback));
}

SAPI.prototype.createApplication = createApplication;


/**
 * Lists all applications
 *
 * @param {Function} callback: of the form f(err, apps).
 */
function listApplications(search_opts, callback) {
    if (arguments.length === 1) {
        callback = search_opts;
        search_opts = {};
    }

    var uri = '/applications?' + qs.stringify(search_opts);
    return (this.get(uri, callback));
}

SAPI.prototype.listApplications = listApplications;


/**
 * Gets an application by UUID
 *
 * @param {String} uuid: the UUID of the applications.
 * @param {Function} callback: of the form f(err, app).
 */
function getApplication(uuid, callback) {
    return (this.get(sprintf('/applications/%s', uuid), callback));
}

SAPI.prototype.getApplication = getApplication;


/**
 * Updates an application
 *
 * @param {String} uuid: the UUID of the applications.
 * @param {String} opts: new attributes
 * @param {Function} callback: of the form f(err, app).
 */
function updateApplication(uuid, opts, callback) {
    assert.string(uuid, 'uuid');
    assert.object(opts, 'opts');

    return (this.put(sprintf('/applications/%s', uuid), opts, callback));
}

SAPI.prototype.updateApplication = updateApplication;


/**
 * Deletes  an application by UUID
 *
 * @param {String} uuid: the UUID of the applications.
 * @param {Function} callback : of the form f(err).
 */
function deleteApplication(uuid, callback) {
    return (this.del(sprintf('/applications/%s', uuid), callback));
}

SAPI.prototype.deleteApplication = deleteApplication;



// --- Services

/**
 * Create a service
 *
 * @param {Function} callback: of the form f(err, app).
 */
function createService(name, application_uuid, opts, callback) {
    assert.string(name, 'name');
    assert.string(application_uuid, 'application_uuid');

    if (typeof (opts) === 'function') {
        callback = opts;
        opts = {};
    }

    opts.name = name;
    opts.application_uuid = application_uuid;

    return (this.post('/services', opts, callback));
}

SAPI.prototype.createService = createService;


/**
 * Lists all services
 *
 * @param {Function} callback: of the form f(err, apps).
 */
function listServices(search_opts, callback) {
    if (arguments.length === 1) {
        callback = search_opts;
        search_opts = {};
    }

    var uri = '/services?' + qs.stringify(search_opts);
    return (this.get(uri, callback));
}

SAPI.prototype.listServices = listServices;


/**
 * Gets a service by UUID
 *
 * @param {String} uuid: the UUID of the services.
 * @param {Function} callback: of the form f(err, app).
 */
function getService(uuid, callback) {
    return (this.get(sprintf('/services/%s', uuid), callback));
}

SAPI.prototype.getService = getService;


/**
 * Updates a service
 *
 * @param {String} uuid: the UUID of the services.
 * @param {String} opts: Optional attributes per
 *      <https://mo.joyent.com/docs/sapi/master/#UpdateService>
 * @param {Function} callback: of the form f(err, app).
 */
function updateService(uuid, opts, callback) {
    assert.string(uuid, 'uuid');
    assert.object(opts, 'opts');

    return (this.put(sprintf('/services/%s', uuid), opts, callback));
}

SAPI.prototype.updateService = updateService;


/**
 * Deletes a service by UUID
 *
 * @param {String} uuid: the UUID of a service.
 * @param {Function} callback : of the form f(err).
 */
function deleteService(uuid, callback) {
    return (this.del(sprintf('/services/%s', uuid), callback));
}

SAPI.prototype.deleteService = deleteService;



// --- Instances

/**
 * Create an instance
 *
 * @param {String} service_uuid: The UUID of the service for which to create
 *      an instance.
 * @param {String} opts: Optional attributes per
 *      <https://mo.joyent.com/docs/sapi/master/#CreateInstance>
 * @param {Function} callback: of the form f(err, instance).
 */
function createInstance(service_uuid, opts, callback) {
    assert.string(service_uuid, 'service_uuid');
    if (typeof (opts) === 'function') {
        callback = opts;
        opts = {};
    }
    assert.object(opts, 'opts');
    assert.func(callback, 'callback');

    opts.service_uuid = service_uuid;

    return (this.post('/instances', opts, callback));
}

SAPI.prototype.createInstance = createInstance;


/**
 * Lists all instances
 *
 * @param {Function} callback: of the form f(err, instances).
 */
function listInstances(search_opts, callback) {
    if (arguments.length === 1) {
        callback = search_opts;
        search_opts = {};
    }

    var uri = '/instances?' + qs.stringify(search_opts);
    return (this.get(uri, callback));
}

SAPI.prototype.listInstances = listInstances;


/**
 * Gets an instance by UUID
 *
 * @param {String} uuid: the UUID of the instance.
 * @param {Function} callback: of the form f(err, instance).
 */
function getInstance(uuid, callback) {
    return (this.get(sprintf('/instances/%s', uuid), callback));
}

SAPI.prototype.getInstance = getInstance;

/**
 * Reprovision an instance
 *
 * @param {String} uuid: the UUID of the instances.
 * @param {String} image_uuid: new attributes
 * @param {Function} callback: of the form f(err, app).
 */
function reprovisionInstance(uuid, image_uuid, callback) {
    assert.string(uuid, 'uuid');
    assert.string(image_uuid, 'image_uuid');

    var opts = {};
    opts.image_uuid = image_uuid;

    return (this.put(sprintf('/instances/%s/upgrade', uuid), opts, callback));
}

SAPI.prototype.reprovisionInstance = reprovisionInstance;



/**
 * Updates an instance
 *
 * @param {String} uuid: the UUID of the instances.
 * @param {String} opts: new attributes
 * @param {Function} callback: of the form f(err, app).
 */
function updateInstance(uuid, opts, callback) {
    assert.string(uuid, 'uuid');
    assert.object(opts, 'opts');

    return (this.put(sprintf('/instances/%s', uuid), opts, callback));
}

SAPI.prototype.updateInstance = updateInstance;


/**
 * Deletes an instance by UUID
 *
 * @param {String} uuid: the UUID of an instance.
 * @param {Function} callback : of the form f(err).
 */
function deleteInstance(uuid, callback) {
    return (this.del(sprintf('/instances/%s', uuid), callback));
}

SAPI.prototype.deleteInstance = deleteInstance;

/**
 * Get the actual payload passed to VMAPI.createVm() for this instance.
 *
 * @param {String} uuid: the UUID of an instance.
 * @param {Function} callback : of the form f(err, payload).
 */
function getInstancePayload(uuid, callback) {
    return (this.get(sprintf('/instances/%s/payload', uuid), callback));
}

SAPI.prototype.getInstancePayload = getInstancePayload;

// --- Manifests

/**
 * Create a manifest
 *
 * @param {Function} callback: of the form f(err, app).
 */
function createManifest(manifest, callback) {
    assert.object(manifest, 'manifest');
    assert.string(manifest.name, 'manifest.name');
    assert.string(manifest.template, 'manifest.template');
    assert.string(manifest.path, 'manifest.path');

    return (this.post('/manifests', manifest, callback));
}

SAPI.prototype.createManifest = createManifest;


/**
 * Lists all manifests
 *
 * @param {Function} callback: of the form f(err, manifests).
 */
function listManifests(callback) {
    return (this.get('/manifests', callback));
}

SAPI.prototype.listManifests = listManifests;


/**
 * Gets a manifest by UUID
 *
 * @param {String} uuid: the UUID of the manifest.
 * @param {Function} callback: of the form f(err, manifest).
 */
function getManifest(uuid, callback) {
    return (this.get(sprintf('/manifests/%s', uuid), callback));
}

SAPI.prototype.getManifest = getManifest;


/**
 * Deletes a manifest by UUID
 *
 * @param {String} uuid: the UUID of a manifest.
 * @param {Function} callback : of the form f(err).
 */
function deleteManifest(uuid, callback) {
    return (this.del(sprintf('/manifests/%s', uuid), callback));
}

SAPI.prototype.deleteManifest = deleteManifest;



// -- Configs

function getConfig(uuid, callback) {
    assert.string(uuid, 'uuid');
    assert.func(callback, 'callback');

    return (this.get(sprintf('/configs/%s', uuid), callback));
}

SAPI.prototype.getConfig = getConfig;



// -- Modes

function getMode(callback) {
    assert.func(callback, 'callback');

    return (this.get('/mode', callback));
}

SAPI.prototype.getMode = getMode;

function setMode(mode, callback) {
    assert.string(mode, 'mode');
    assert.func(callback, 'callback');

    return (this.post(sprintf('/mode?mode=%s', mode), {}, callback));
}

SAPI.prototype.setMode = setMode;



// -- Payloads

SAPI.prototype.getPayload = function getPayload(uuid, callback) {
    assert.string(uuid, 'uuid');
    assert.func(callback, 'callback');

    return (this.get(sprintf('/instances/%s/payload', uuid), callback));
};

module.exports = SAPI;



// -- Helper functions

SAPI.prototype.getApplicationObjects = getApplicationObjects;
SAPI.prototype.getOrCreateApplication = getOrCreateApplication;
SAPI.prototype.getOrCreateService = getOrCreateService;
SAPI.prototype.readManifest = readManifest;
SAPI.prototype.readAndMergeFiles = readAndMergeFiles;
SAPI.prototype.loadManifests = loadManifests;
SAPI.prototype.whatis = whatis;


function readJsonFile(file, cb) {
    var log = this.log;

    assert.string(file, 'file');
    assert.func(cb, 'cb');

    fs.readFile(file, 'ascii', function (err, contents) {
        if (err) {
            log.error(err, 'failed to read file %s', file);
            return (cb(err));
        }

        var obj;
        try {
            obj = JSON.parse(contents);
        } catch (e) {
            var err = new Error('invalid JSON in ' + file);
            return (cb(err));
        }

        return (cb(null, obj));
    });
}

function mergeOptions(opts1, opts2) {
    assert.object(opts1, 'opts1');
    assert.optionalObject(opts2, 'opts2');

    var opts = {};
    opts.params = {};
    opts.metadata = {};

    if (opts1.params)
        opts.params = opts1.params;
    if (opts1.metadata)
        opts.metadata = opts1.metadata;

    if (opts2 && opts2.params) {
        Object.keys(opts2.params).forEach(function (key) {
            opts.params[key] = opts2.params[key];
        });
    }
    if (opts2 && opts2.metadata) {
        Object.keys(opts2.metadata).forEach(function (key) {
            opts.metadata[key] = opts2.metadata[key];
        });
    }

    if (opts2 && opts2.master)
        opts.master = opts2.master;
    if (opts2 && opts2.type)
        opts.type = opts2.type;

    return (opts);
}

/*
 * Deep merges o2 into o1.  Note that it doesn't do deep copying, it assumes
 * that the two objects shouldn't be used independently foreverafter.
 */
function _merge(o1, o2) {
    Object.keys(o2).forEach(function (k) {
        if (o1[k] === undefined) {
            o1[k] = o2[k];
        } else {
            if ((typeof (o1[k])) === 'object') {
                _merge(o1[k], o2[k]);
            } else { // Last property wins!
                o1[k] = o2[k];
            }
        }
    });
}

/*
 * Merges the set of objects into a single object.  Last property wins.  Only
 * objects are merged, not arrays (that may need to change at some point).
 */
function merge() {
    assert.object(arguments[0]);
    var obj = {};
    for (var i = 0; i < arguments.length; ++i) {
        _merge(obj, arguments[i]);
    }
    return (obj);
}

/*
 * Reads a set of files and merges them, per the merge function above.  This
 * only throws if the first file isn't found (as weird as this sounds, it
 * happens to be the behavior that we need.
 */
function readAndMergeFiles(files, cb) {
    assert.func(cb);
    if ((typeof (files)) === 'string') {
        files = [ files ];
    }
    assert.arrayOfString(files, 'files');
    var objs = [];
    function end() {
        cb(null, merge.apply(this, objs));
    }
    var i = 0;
    function next() {
        var file = files[i];
        if (!file) {
            end();
            return;
        }

        fs.stat(file, function (err, stat) {
            if (err && err.code === 'ENOENT' && i != 0) {
                ++i;
                next();
                return;
            }
            if (err) {
                cb(err);
                return;
            }

            readJsonFile(file, function (err, s) {
                if (err) {
                    cb(err);
                }
                objs.push(s);
                ++i;
                next();
            });
        });
    }
    next();
}

/*
 * getApplicationObjects - get all services and instances contained in a given
 *   application.  Returns an object with two fields, "services" and
 *   "instances".  The "services" field maps each service's UUID to its service
 *   definition, and the "instances" field maps each service's UUID to a list of
 *   associated instances.
 */
function getApplicationObjects(app_uuid, opts, cb) {
    var self = this;

    if (arguments.length === 2) {
        cb = opts;
        opts = {};
    }

    assert.string(app_uuid, 'app_uuid');
    assert.func(cb, 'cb');

    var ret = {};

    async.waterfall([
        function (subcb) {
            var search_opts = {};
            search_opts.application_uuid = app_uuid;

            if (opts.include_master)
                search_opts.include_master = true;

            self.listServices(search_opts, function (err, svcs) {
                if (err)
                    return (subcb(err));

                ret.services = {};
                svcs.forEach(function (svc) {
                    ret.services[svc.uuid] = svc;
                });

                return (subcb());
            });
        },
        function (subcb) {
            ret.instances = {};

            var search_opts = {};
            if (opts.include_master)
                search_opts.include_master = true;

            self.listInstances(search_opts, function (err, insts) {
                if (err)
                    return (subcb(err));

                /*
                 * The listInstances() call returns all instances, not just
                 * those contained within the application.  To see if an
                 * instance should be included, check its service_uuid to see it
                 * it refers to a service within the given application.
                 */
                insts.forEach(function (inst) {
                    var svc_uuid = inst.service_uuid;
                    if (!ret.services[svc_uuid])
                        return;
                    if (!ret.instances[svc_uuid])
                        ret.instances[svc_uuid] = [];
                    ret.instances[svc_uuid].push(inst);
                });

                return (subcb());
            });
        }
    ], function (err) {
        if (err)
            return (cb(err));

        assert.object(ret, 'ret');
        assert.object(ret.services, 'ret.services');
        assert.object(ret.instances, 'ret.instances');

        return (cb(null, ret));
    });
}

/*
 * getOrCreateApplication - get or create a SAPI application
 *
 * This function either gets a SAPI application (if already exists) or creates
 * it (if it doesn't exist).  It's arguments are:
 *
 *     name - application name
 *     owner_uuid - application owner
 *     files - names of files which contains params and metadata for this
 *         application.  All file contents will become merged, with the
 *         *last* properties "winning" (so that later files override earlier
 *         files).
 *     extra_opts - extra params and metadata which are merged with the
 *         properties from `file`
 */
function getOrCreateApplication(name, owner_uuid, files, extra_opts, cb) {
    var self = this;
    var log = this.log;

    assert.string(name, 'name');
    assert.string(owner_uuid, 'owner_uuid');
    assert.ok(files, 'files'); // string or list of strings

    if (arguments.length === 4) {
        cb = extra_opts;
        extra_opts = null;
    }

    assert.func(cb, 'cb');

    log.info({
        name: name,
        owner_uuid: owner_uuid
    }, 'getting or creating application');

    async.waterfall([
        function (subcb) {
            var search = {};
            search.name = name;
            search.owner_uuid = owner_uuid;

            if (extra_opts && extra_opts.include_master)
                search.include_master = true;

            self.listApplications(search, function (err, apps) {
                if (err) {
                    log.error(err, 'failed to list applications');
                    return (subcb(err));
                }

                if (apps.length > 0) {
                    log.debug({ app: apps[0] }, 'found application %s', name);
                    return (cb(null, apps[0]));
                }

                return (subcb(null));
            });
        },
        function (subcb) {
            readAndMergeFiles(files, function (err, obj) {
                if (err)
                    return (subcb(err));

                return (subcb(null, mergeOptions(obj, extra_opts)));
            });
        },
        function (opts, subcb) {
            assert.object(opts, 'opts');
            assert.func(subcb, 'subcb');

            self.createApplication(name, owner_uuid, opts,
                function (err, app) {
                if (err) {
                    log.error(err, 'failed to create ' +
                        'application %s', name);
                    return (subcb(err));
                }

                log.info('created application %s', app.uuid);
                return (subcb(null, app));
            });
        }
    ], cb);
}



/*
 * getOrCreateService - get or create a SAPI service
 *
 * This function either gets a SAPI service (if already exists) or creates
 * it (if it doesn't exist).  It's arguments are:
 *
 *     name - service name
 *     application_uuid - application to which service belongs
 *     files - names of files which contains params and metadata for this
 *         service.  All file contents will become merged, with the
 *         *last* properties "winning" (so that later files override earlier
 *         files).
 *     extra_opts - extra params and metadata which are merged with the
 *         properties from `file`
 */
function getOrCreateService(name, application_uuid, files, extra_opts, cb) {
    var self = this;
    var log = self.log;

    assert.string(name, 'name');
    assert.string(application_uuid, 'application_uuid');
    assert.ok(files, 'files');  // string or list of strings

    if (arguments.length === 4) {
        cb = extra_opts;
        extra_opts = null;
    }

    assert.func(cb, 'cb');

    log.info({
        name: name,
        application_uuid: application_uuid
    }, 'getting or creating service');

    async.waterfall([
        function (subcb) {
            var search = {};
            search.name = name;
            search.application_uuid = application_uuid;

            if (extra_opts && extra_opts.include_master)
                search.include_master = true;

            self.listServices(search, function (err, svcs) {
                if (err) {
                    log.error(err, 'failed to list services');
                    return (subcb(err));
                }

                if (svcs.length > 0) {
                    log.debug({ svc: svcs[0] }, 'found service %s', name);
                    return (cb(err, svcs[0]));
                }

                return (subcb(null));
            });
        },
        function (subcb) {
            readAndMergeFiles(files, function (err, obj) {
                if (err)
                    return (subcb(err));

                return (subcb(null, mergeOptions(obj, extra_opts)));
            });
        },
        function (opts, subcb) {
            assert.object(opts, 'opts');
            assert.func(subcb, 'subcb');

            log.debug({ opts: opts }, 'creating service');

            self.createService(name, application_uuid, opts,
                function (err, svc) {
                if (err) {
                    log.error(err, 'failed to create service %s', name);
                    return (subcb(err));
                }

                log.info({ svc: svc },
                    'created service %s', name);

                return (subcb(err, svc));
            });
        }
    ], cb);
}


function readManifest(dirname, cb) {
    var log = this.log;

    async.waterfall([
        function (subcb) {
            var file = path.join(dirname, 'manifest.json');

            fs.readFile(file, 'ascii', function (err, contents) {
                if (err) {
                    log.error(err, 'failed to read %s', file);
                    return (subcb(err));
                }

                var manifest;
                try {
                    manifest = JSON.parse(contents);
                } catch (e) {
                    err = new Error('invalid JSON in ' + file);
                    log.error(err, 'failed to read %s', file);
                    return (subcb(err));
                }

                assert.object(manifest);
                assert.string(manifest.name);
                assert.string(manifest.path);

                return (subcb(null, manifest));
            });
        },
        function (manifest, subcb) {
            assert.object(manifest);
            assert.string(manifest.name);
            assert.string(manifest.path);

            var file = path.join(dirname, 'template');

            fs.readFile(file, 'ascii', function (err, template) {
                if (err) {
                    log.error(err, 'failed to read file %s',
                        file);
                    return (subcb(err));
                }

                manifest.template = template;
                return (subcb(null, manifest));
            });
        }
    ], cb);
}

function loadManifest(dirname, cb) {
    var self = this;
    var log = this.log;

    log.info('creating configuration manifest from %s', dirname);

    async.waterfall([
        function (subcb) {
            readManifest(dirname, subcb);
        },
        function (manifest, subcb) {
            assert.object(manifest);
            assert.string(manifest.name);
            assert.string(manifest.path);
            assert.string(manifest.template);

            var name = path.basename(dirname);
            manifest.name = name;

            self.createManifest(manifest, function (err, obj) {
                if (err) {
                    log.error(err,
                        'failed to add manifest');
                    return (subcb(err));
                }

                assert.object(obj, 'obj');
                assert.string(obj.uuid, 'obj.uuid');

                var result = {};
                result[name] = obj.uuid;

                return (subcb(null, result));
            });
        }
    ], cb);
}


/*
 * loadManifests - load and create manifests from a directory
 *
 * This function expects a directory with the following structure:
 *
 *     manifests/mako
 *     manifests/mako/template
 *     manifests/mako/manifest.json
 *     manifests/minnow
 *     manifests/minnow/template
 *     manifests/minnow/manifest.json
 *
 * In that case, calling loadManifests('manifests') would create two manifests:
 * one for mako and a second for minnow.
 */
function loadManifests(dirname, cb) {
    assert.string(dirname, 'dirname');
    assert.func(cb, 'cb');

    var self = this;
    var log = self.log;

    log.info('loading configuration manifests from %s', dirname);

    fs.readdir(dirname, function (err, files) {
        if (err) {
            log.warn(err, 'failed to read directory %s', dirname);
            return (cb(null, []));
        }

        vasync.forEachParallel({
            func: function (item, subcb) {
                loadManifest.call(self,
                    path.join(dirname, item), subcb);
            },
            inputs: files
        }, function (suberr, results) {
            if (suberr)
                return (cb(suberr));

            var result = {};
            results.successes.forEach(function (item) {
                assert.object(item, 'item');
                assert.ok(Object.keys(item).length === 1);

                var key = Object.keys(item)[0];
                result[key] = item[key];
            });

            return (cb(suberr, result));
        });

        return (null);
    });
}

/*
 * whatis - get either an application, service, or instance by UUID
 */
function whatis(uuid, cb) {
    assert.string(uuid, 'uuid');
    assert.func(cb, 'cb');

    var self = this;

    async.waterfall([
        function (subcb) {
            self.getApplication(uuid, function (err, app) {
                if (err && err.statusCode !== 404)
                    return (cb(err));
                if (app) {
                    app.type = 'application';
                    return (cb(null, app));
                }

                return (subcb(null));
            });
        },
        function (subcb) {
            self.getService(uuid, function (err, svc) {
                if (err && err.statusCode !== 404)
                    return (cb(err));
                if (svc) {
                    svc.type = 'service';
                    return (cb(null, svc));
                }

                return (subcb(null));
            });
        },
        function (subcb) {
            self.getInstance(uuid, function (err, inst) {
                if (err && err.statusCode !== 404)
                    return (cb(err));
                if (inst) {
                    inst.type = 'instance';
                    return (cb(null, inst));
                }

                return (subcb(null));
            });
        }
    ], function () {
        cb(null, null);
    });
}
