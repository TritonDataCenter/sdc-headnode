/*
 * Copyright (c) 2013, Joyent, Inc. All rights reserved.
 *
 * Client library for the SDC Packages API (PAPI)
 */

var util = require('util');
var format = util.format;
var restify = require('restify');
var qs = require('querystring');
var assertions = require('./assertions');

// --- Globals

var assertFunction = assertions.assertFunction;
var assertNumber = assertions.assertNumber;
var assertObject = assertions.assertObject;
var assertString = assertions.assertString;

var ResourceNotFoundError = restify.ResourceNotFoundError;


// Note this is not a constructor!.
function PAPI(options) {
    if (typeof (options) !== 'object') {
        throw new TypeError('options (Object) required');
    }

    if (typeof (options.url) !== 'string') {
        throw new TypeError('options.url (String) required');
    }

    if (!options['X-Api-Version']) {
        options['X-Api-Version'] = '~7.0';
    }

    var client = restify.createJsonClient(options);


    /**
     * Adds a new package to PAPI
     *
     * See https://mo.joyent.com/docs/papi/master/#packageobjects for the
     * details on expected attributes
     *
     * @param {Object} pkg the entry to add.
     * @param {Function} cb of the form fn(err, pkg).
     * @throws {TypeError} on bad input.
     */
    function add(pkg, cb) {
        assertObject('pkg', pkg);
        assertFunction('cb', cb);

        return client.post('/packages', pkg, function (err, req, res, pkg) {
            if (err) {
                return cb(err);
            }
            return cb(null, pkg);
        });
    }


    /**
     * Looks up a package by uuid.
     *
     * @param {String} uuid for a package.
     * @param {Object} options params passed to PAPI
     * @param {Function} cb of the form f(err, pkg).
     * @throws {TypeError} on bad input.
     */
    function get(uuid, options, cb) {
        assertString('uuid', uuid);
        assertObject('options', options);
        assertFunction('cb', cb);

        var path = createPath('/packages/' + uuid, options);

        return client.get(path, function (err, req, res, pkg) {
            if (err) {
                return cb(err);
            }

            return cb(null, pkg);
        });
    }


    /**
     * Deletes a pkg record.
     *
     * @param {String} uuid the uuid of the record you received from get().
     * @param {Object} opt the uuid of the record you received from get().
     * @param {Function} cb of the form fn(err).
     * @throws {TypeError} on bad input.
     */
    function del(uuid, options, cb) {
        assertString('uuid', uuid);
        assertObject('options', options);
        assertFunction('cb', cb);

        var path = createPath('/packages/' + uuid, options);

        return client.del(path, cb);
    }


    /**
     * Updates a package record.
     *
     * Note you don't need to pass a whole copy of the pkg to changes, just the
     * attributes you want to modify
     *
     * @param {Object} pkg the package record you got from get.
     * @param {Object} changes the pkg to *replace* original package with
     * @param {Function} cb of the form fn(err).
     * @throws {TypeError} on bad input.
     */
    function update(uuid, changes, cb) {
        assertString('uuid', uuid);
        assertObject('changes', changes);
        assertFunction('cb', cb);

        var p = '/packages/' + uuid;
        return client.put(p, changes, function (err, req, res, pack) {
            if (err) {
                return cb(err);
            }

            return cb(null, pack);
        });
    }


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
     * When passing a filter object (not a string), the query arguments will be
     * escaped according to ldif filter rules. This can be overridden with an
     * option, but don't do so unless you're 100% confident the query args
     * aren't potentially tainted.
     *
     * @param {String or Object} provided LDAP filter.
     * @param {Object} pagination options when desired.
     * @param {Function} callback cb of the form fn(err, pkgs, count).
     * @throws {TypeError} on bad input.
     */
    function list(filter, options, cb) {
        assertObject('options', options);
        assertFunction('cb', cb);

        var escape = options.escape;
        delete options.escape;

        var q = [];

        if (typeof (filter) === 'string') {
            q.push('filter=' + escapeParam(filter, false));
        } else {
            Object.keys(filter).forEach(function (k) {
                q.push(k + '=' + escapeParam(filter[k], escape));
            });
        }

        Object.keys(options).forEach(function (k) {
            q.push(k + '=' + options[k]);
        });

        var p = '/packages';

        if (q.length) {
            p = p + '?' + q.join('&');
        }

        return client.get(p, function (err, req, res, pkgs) {
            if (err) {
                return cb(err);
            }

            var count = Number(res.headers['x-resource-count']);
            return cb(null, pkgs, count);
        });
    }


   /**
    * Escapes param data being sent to PAPI.
    *
    * PAPI accepts special characters used for LDIF filters in its params
    * when making queries. This is useful for ops, but undesirable for
    * most applications (and especially data that may carry taint from
    * outside). This function escapes data (both ldif and query forms) so
    * that they're safe to use as params passed to PAPI.
    *
    * @param data the data to escape
    * @param escape whether to escape the data for ldif
    */
    function escapeParam(data, escape) {
        if (typeof (data) !== 'string')
            return data;

        // treat undefined as true as well
        if (escape !== false) {
            data = data.replace('(',  '{\\28}').
                        replace(')',  '{\\29}').
                        replace('\\', '{\\5c}').
                        replace('*',  '{\\2a}').
                        replace('/',  '{\\2f}');
        }

        return qs.escape(data);
    }


   /**
    * Append params to path.
    *
    * @param {String} path the path without params
    * @param {Object} options the args to apply to the end of the path
    */
    function createPath(path, options) {
        assertString('path', path);
        assertObject('options', options);

        var escape = options.escape;
        delete options.escape;

        var q = [];

        Object.keys(options).forEach(function (k) {
            q.push(k + '=' + escapeParam(options[k], escape));
        });

        if (q.length)
            path += '?' + q.join('&');

        return path;
    }


    return {
        add: add,
        get: get,
        list: list,
        del: del,
        update: update,
        client: client
    };
}

module.exports = PAPI;
