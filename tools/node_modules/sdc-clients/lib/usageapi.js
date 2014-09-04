/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * Client library for the SDC Usage API (UsageAPI)
 */

var util = require('util');
var format = util.format;
var restify = require('restify');
var qs = require('querystring');


// Note this is not a constructor!.
function UsageAPI(options) {
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

    if (options.username && options.password) {
        client.basicAuth(options.username, options.password);
    }

    return {
        generateReport: function generateReport(opts, callback) {
            if (typeof (opts) !== 'object') {
                throw new TypeError('opts (Object) required');
            }

            if (opts.owners && Array.isArray(opts.owners)) {
                opts.owners = opts.owners.join(',');
            }

            if (opts.ips && Array.isArray(opts.ips)) {
                opts.ips = opts.ips.join(',');
            }

            if (opts.vms && Array.isArray(opts.vms)) {
                opts.vms = opts.vms.join(',');
            }

            var path = '/usage?' + qs.stringify(opts);
            return client.post(path, {}, function (err, req, res, obj) {
                if (err) {
                    return callback(err);
                }
                return callback(null, res.headers.location);
            });

        },

        getReport: function getReport(opts, callback) {
            var path;

            if (typeof (opts) === 'string') {

                path = opts;

            } else {

                if (typeof (opts) !== 'object') {
                    throw new TypeError('opts (Object) required');
                }

                if (opts.owners && Array.isArray(opts.owners)) {
                    opts.owners = opts.owners.join(',');
                }

                if (opts.ips && Array.isArray(opts.ips)) {
                    opts.ips = opts.ips.join(',');
                }

                if (opts.vms && Array.isArray(opts.vms)) {
                    opts.vms = opts.vms.join(',');
                }

                path = '/usage?' + qs.stringify(opts);
            }

            return client.get({
                path: path,
                headers:  {
                    'Accept-Encoding': 'gzip'
                }
            }, function (err, req, res, obj) {
                if (err) {
                    return callback(err);
                }

                return callback(null, {
                    status: res.headers['x-report-status'],
                    report: obj
                });
            });
        }
    };
}

module.exports = UsageAPI;
