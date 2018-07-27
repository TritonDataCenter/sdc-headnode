/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2018, Joyent, Inc.
 */

/*
 * Client library for the Triton Packages API (PAPI)
 */

var assert = require('assert-plus');
var restifyClients = require('restify-clients');


// ---- client

function PAPI(clientOpts) {
    /*
     * At one time, the `PAPI` export was not written to be a constructor,
     * so usage was:
     *      var client = PAPI(...);
     * We want to move to the preferred:
     *      var client = new PAPI(...);
     * without breaking the old usage.
     */
    if (!(this instanceof PAPI)) {
        return new PAPI(clientOpts);
    }

    assert.object(clientOpts, 'clientOpts');
    assert.string(clientOpts.url, 'clientOpts.url');
    assert.optionalObject(clientOpts.contentMd5, 'clientOpts.contentMd5');

    // JSSTYLED
    // Per https://github.com/joyent/triton/blob/master/docs/developer-guide/coding-guidelines-node.md#restify-clients-contentmd5-option
    if (!clientOpts.contentMd5) {
        clientOpts.contentMd5 = {
            encodings: ['utf8', 'binary']
        };
    }

    if (!clientOpts['X-Api-Version']) {
        clientOpts['X-Api-Version'] = '~7.0';
    }

    this.client = restifyClients.createJsonClient(clientOpts);

    return undefined;
}


/**
 * Adds a new package to PAPI
 *
 * See https://mo.joyent.com/docs/papi/master/#packageobjects for the
 * details on expected attributes
 *
 * @param {Object} pkg the entry to add.
 * @param {Object} request options.
 * @param {Function} cb of the form fn(err, pkg).
 * @throws {TypeError} on bad input.
 */
PAPI.prototype.add = function add(pkg, options, cb) {
    var self = this;

    if (typeof (options) === 'function') {
        cb = options;
        options = {};
    }

    assert.object(pkg, 'pkg');
    assert.func(cb, 'cb');

    var opts = {path: '/packages'};
    if (options.headers) {
        opts.headers = options.headers;
    }

    return self.client.post(opts, pkg, function (err, req, res, createdPkg) {
        if (err) {
            return cb(err);
        }
        return cb(null, createdPkg);
    });
};


/**
 * Looks up a package by uuid.
 *
 * Although this is a GET, it is possible to pass additional arguments to PAPI
 * through the 'options' parameter.
 *
 * Be aware that when additional options are provided, option values which are
 * strings will have PAPI wildcards (i.e. '*') escaped. This can be overridden
 * with an option (escape = false), but don't do so unless you want to give
 * any callers the ability to wildcard search.
 *
 * @param {String} uuid for a package.
 * @param {Object} options params passed to PAPI
 * @param {Function} cb of the form f(err, pkg).
 * @throws {TypeError} on bad input.
 */
PAPI.prototype.get = function get(uuid, options, cb) {
    var self = this;

    assert.uuid(uuid, 'uuid');
    assert.object(options, 'options');
    assert.optionalObject(options.headers, 'options.headers');
    assert.optionalBool(options.escape, 'options.escape');
    assert.func(cb, 'cb');

    var escape = (options.escape === undefined ? true : options.escape);
    var headers = options.headers;
    delete options.escape;
    delete options.headers;

    var query = {};

    Object.keys(options).forEach(function (k) {
        var val = options[k];

        if (escape && typeof (val) === 'string') {
            /* JSSTYLED */
            query[k] = val.replace(/\*/g, '{\\2a}');
        } else {
            query[k] = val;
        }
    });

    var opts = {
        path: '/packages/' + uuid,
        query: query
    };

    if (headers) {
        opts.headers = headers;
    }

    return self.client.get(opts, function (err, req, res, pkg) {
        if (err) {
            return cb(err);
        }

        return cb(null, pkg);
    });
};



/**
 * Deletes a pkg record.
 *
 * This is a risky endpoint to call -- see the PAPI docs regarding the
 * DeletePackage endpoint for more details. As a result, this call will
 * always fail unless you explicitly set 'options.force' to true.
 *
 * @param {String} uuid the uuid of the record you received from get().
 * @param {Object} opt the uuid of the record you received from get().
 * @param {Function} cb of the form fn(err).
 * @throws {TypeError} on bad input.
 */
PAPI.prototype.del = function del(uuid, options, cb) {
    var self = this;

    assert.uuid(uuid, 'uuid');
    assert.object(options, 'options');
    assert.optionalObject(options.headers, 'options.headers');
    assert.optionalBool(options.force, 'options.force');
    assert.func(cb, 'cb');

    var opts = {
        path: '/packages/' + uuid
    };

    if (options.force) {
        opts.query = { force: true };
    }

    if (options.headers) {
        opts.headers = options.headers;
    }

    return self.client.del(opts, cb);
};


/**
 * Updates a package record.
 *
 * Note you don't need to pass a whole copy of the pkg to changes, just the
 * attributes you want to modify
 *
 * @param {Object} pkg the package record you got from get.
 * @param {Object} changes the pkg to *replace* original package with
 * @param {Object} request options.
 * @param {Function} cb of the form fn(err).
 * @throws {TypeError} on bad input.
 */
PAPI.prototype.update = function update(uuid, changes, options, cb) {
    var self = this;


    if (typeof (options) === 'function') {
        cb = options;
        options = {};
    }

    assert.uuid(uuid, 'uuid');
    assert.object(changes, 'changes');
    assert.func(cb, 'cb');

    var p = '/packages/' + uuid;
    var opts = {path: p};
    if (options.headers) {
        opts.headers = options.headers;
    }
    return self.client.put(opts, changes, function (err, req, res, pack) {
        if (err) {
            return cb(err);
        }

        return cb(null, pack);
    });
};


/**
 * Loads a list of packages.
 *
 * If the filter is a string, it will be fed as an LDIF filter directly to
 * PAPI. If it is a hash, each k/v pair will be passed to PAPI as
 * constraints on the query.
 *
 * See https://mo.joyent.com/docs/papi/master/#ListPackages for detailed
 * information regarding search filter and pagination options accepted
 *
 * The count argument retrieved on success will provide the total number
 * of packages matching the given search filter (retrieved by PAPI as
 * x-resource-count HTTP header).
 *
 * When passing a filter object (not a string), the query arguments will
 * escape PAPI ListPackage wildcards. This can be overridden with an
 * option (escape = false), but don't do so unless you want to give any
 * callers the ability to wildcard search.
 *
 * @param {String or Object} provided LDAP filter.
 * @param {Object} pagination options when desired.
 * @param {Function} callback cb of the form fn(err, pkgs, count).
 * @throws {TypeError} on bad input.
 */
PAPI.prototype.list = function list(filter, options, cb) {
    var self = this;

    assert.object(options, 'options');
    assert.optionalBool(options.escape, 'options.escape');
    assert.optionalObject(options.headers, 'options.headers');
    assert.func(cb, 'cb');

    var escape = (options.escape === undefined ? true : options.escape);
    var headers = options.headers;
    delete options.escape;
    delete options.headers;

    var query = {};

    if (typeof (filter) === 'string') {
        query.filter = filter;
    } else {
        Object.keys(filter).forEach(function (k) {
            var val = filter[k];

            if (escape && typeof (val) === 'string') {
                /* JSSTYLED */
                query[k] = val.replace(/\*/g, '{\\2a}');
            } else {
                query[k] = val;
            }
        });
    }

    Object.keys(options).forEach(function (k) {
        query[k] = options[k];
    });

    var opts = {
        path: '/packages',
        query: query
    };

    if (headers) {
        opts.headers = headers;
    }

    return self.client.get(opts, function (err, req, res, pkgs) {
        if (err) {
            return cb(err);
        }

        var count = Number(res.headers['x-resource-count']);
        return cb(null, pkgs, count);
    });
};



/**
 * Terminate any open connections to the PAPI service.
 */
PAPI.prototype.close = function close() {
    var self = this;

    self.client.close();
};


module.exports = PAPI;
