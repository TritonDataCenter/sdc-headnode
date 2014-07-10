/*
 * Copyright (c) 2012, Joyent, Inc. All rights reserved.
 *
 * SDC Packages specific wrapper on top of UFDS.
 */

var util = require('util'),
    UFDS = require('./ufds'),
    ldap = require('ldapjs'),
    restify = require('restify'),
    assertions = require('./assertions'),
    sprintf = util.format;

var libuuid = require('libuuid');
function uuid() {
    return (libuuid.create());
}

// --- Globals

var assertFunction = assertions.assertFunction;
var assertNumber = assertions.assertNumber;
var assertObject = assertions.assertObject;
var assertString = assertions.assertString;

var ResourceNotFoundError = restify.ResourceNotFoundError;

var SUFFIX = 'o=smartdc';
var PACKAGES = 'ou=packages, ' + SUFFIX;
var PKG_FMT = 'uuid=%s, ' + PACKAGES;

// --- Exported API

/**
 * Constructor.
 *
 * Exactly same parameters than UFDS.
 *
 * @param {Object} options options object:
 *   - url {String} UFDS location.
 *   - bindDN {String} admin bind DN for UFDS.
 *   - password {String} password to said admin DN.
 *   - cache {Object} age (default 60s) and size (default 1k).
 *     use false to disable altogether.
 */

function Package(options) {
    this.ufds = (options instanceof UFDS) ? options : new UFDS(options);
}
module.exports = Package;


/**
 * Adds a new package into UFDS.
 *
 * This call expects the package object to look like the `sdcPackage` UFDS
 * schema, minus objectclass/dn/uuid.
 *
 * @param {Object} pkg the entry to add.
 * @param {Function} callback of the form fn(err, pkg).
 * @throws {TypeError} on bad input.
 */
Package.prototype.add = function add(pkg, callback) {
    assertObject('pkg', pkg);
    assertFunction('callback', callback);

    var self = this;

    if (!pkg.uuid) {
        pkg.uuid = uuid();
    }

    pkg.objectclass = 'sdcpackage';

    if (pkg.traits) {
        if (typeof (pkg.traits) === 'object' &&
            Object.keys(pkg.traits).length) {
            pkg.traits = JSON.stringify(pkg.traits);
        } else {
            delete pkg.traits;
        }
    }

    if (pkg.networks && typeof (pkg.networks) !== 'string') {
        pkg.networks = JSON.stringify(pkg.networks);
    } else {
        delete pkg.networks;
    }

    return self.ufds.add(sprintf(PKG_FMT, pkg.uuid), pkg, function (err) {
        if (err) {
            return callback(err);
        }

        return self.get(pkg.uuid, function (err, pkg) {
            if (err) {
                return callback(err);
            }
            return callback(null, pkg);
        });
    });
};


/**
 * Looks up a package by uuid to UFDS.
 *
 * @param {String} uuid for a package.
 * @param {Object} options (optional).
 * @param {Function} callback of the form f(err, pkg).
 * @throws {TypeError} on bad input.
 */
Package.prototype.get = function get(uuid, callback) {
    if (typeof (uuid) !== 'object') {
        assertString('uuid', uuid);
    }
    assertFunction('callback', callback);

    if (typeof (uuid) === 'object') {
        return callback(null, uuid);
    }

    var self = this,
        opts = {
            scope: 'one',
            filter: sprintf('(&(objectclass=sdcpackage)(uuid=%s))', uuid)
        };

    return self.ufds.search(PACKAGES, opts, function (err, entries) {
        var pkg, msg;
        if (err) {
            return callback(err);
        }

        if (entries.length === 0) {
            msg = uuid + ' does not exist';
            return callback(new ResourceNotFoundError(msg));
        }
        pkg = entries[0];
        delete pkg.controls;

        if (pkg.traits) {
            try {
                pkg.traits = JSON.parse(pkg.traits);
            } catch (e) {
                pkg.traits = {};
            }
        }

        if (pkg.networks) {
            try {
                pkg.networks = JSON.parse(pkg.networks);
            } catch (e) {
                pkg.networks = {};
            }
        }

        return callback(null, pkg);
    });
};


/**
 * Updates a package record.
 *
 * @param {Object} pkg the package record you got from getPackage.
 * @param {Object} changes the pkg to *replace* original package with
 * @param {Function} callback of the form fn(err).
 * @throws {TypeError} on bad input.
 */
Package.prototype.update = function update(pkg, changes, callback) {
    assertObject('pkg', pkg);
    assertObject('changes', changes);
    assertFunction('callback', callback);

    if (changes.traits && Object.keys(changes.traits).length) {
        changes.traits = JSON.stringify(changes.traits);
    } else {
        delete changes.traits;
    }

    if (changes.networks && changes.networks.length) {
        changes.networks = JSON.stringify(changes.networks);
    } else {
        delete changes.networks;
    }

    var self = this;
    function _callback(pkg) {
        if (pkg.traits) {
            pkg.traits = JSON.stringify(pkg.traits);
        }
        if (pkg.networks) {
            pkg.networks = JSON.stringify(pkg.networks);
        }
        var _changes = [];
        Object.keys(pkg).forEach(function (k) {
            if (k === 'dn' ||
                k === 'objectclass' ||
                k === 'uuid' ||
                pkg[k] === changes[k] ||
                typeof (changes[k]) === 'function')
            {
                return;
            }

            var change = {
                type: 'replace',
                modification: {}
            };
            if (pkg[k] && !changes[k]) {
                change.type = 'delete';
                change.modification[k] = [];
            } else {
                change.modification[k] = changes[k];
            }

            _changes.push(change);
        });

        // Now we need to loop over the new object to find members not into
        // original object to find additions:
        Object.keys(changes).forEach(function (k) {
            if (k === 'dn' ||
                k === 'objectclass' ||
                k === 'uuid' ||
                pkg[k] === changes[k] ||
                typeof (changes[k]) === 'function') {
                return;
                }

            if (!pkg[k]) {
                var change = {
                    type: 'add',
                    modification: {}
                };
                change.modification[k] = changes[k];
                _changes.push(change);
            } else {
                return;
            }
        });

        if (!_changes.length) {
            return callback(null);
        }

        return self.ufds.modify(pkg.dn, _changes, callback);
    }

    // Force us to retrieve the pkg from backend so we can check the delta
    if (typeof (pkg) === 'object') {
        pkg = pkg.uuid;
    }

    return self.get(pkg, function (err, pkg) {
        if (err) {
            return callback(err);
        }

        return _callback(pkg);
    });
};


/**
 * Deletes a pkg record.
 *
 * @param {Object} pkg the pkg record you got from getPackage.
 * @param {Function} callback of the form fn(err).
 * @throws {TypeError} on bad input.
 */
Package.prototype.del = function del(pkg, callback) {
    assertObject('pkg', pkg);
    assertFunction('callback', callback);

    return callback(new restify.BadMethodError('Packages cannot be deleted'));
};


/**
 * Loads all packages. If filter is provided, it will load only packages
 * matching the given LDAP filter.
 *
 * @param {String} provided LDAP filter. The filter must include the condition
 * '(objectclass=sdcpackage)' or it will not be used.
 * @param {Function} callback of the form fn(err, pkgs).
 * @throws {TypeError} on bad input.
 */
Package.prototype.list = function list(filter, callback) {
    if (typeof (filter) === 'function') {
        callback = filter;
        filter = '(objectclass=sdcpackage)';
    } else {
        /* JSSTYLED */
        if (!/objectclass=sdcpackage/.test(filter)) {
            filter = '(objectclass=sdcpackage)';
        }
    }
    assertString('filter', filter);
    assertFunction('callback', callback);

    var self = this,
        opts = {
            scope: 'sub',
            filter: filter
        };

    return self.ufds.search(PACKAGES, opts, function (err, pkgs) {
        if (err) {
            return callback(err);
        }

        var packages = pkgs || [];
        packages = packages.map(function (pkg) {
            if (pkg.networks) {
                try {
                    pkg.networks = JSON.parse(pkg.networks);
                } catch (e) {
                    pkg.networks = {};
                }
            }
            if (pkg.traits) {
                try {
                    pkg.traits = JSON.parse(pkg.traits);
                } catch (e) {
                    pkg.traits = {};
                }
            }
            return (pkg);
        });

        return callback(null, packages);
    });

};
