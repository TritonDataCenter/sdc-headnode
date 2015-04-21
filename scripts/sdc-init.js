#!/usr/node/bin/node
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * sdc-init.js: initializes sdc SAPI application definition.
 */

var assert = require('/opt/smartdc/node_modules/assert-plus');
var async = require('/usr/node/node_modules/async');
var cp = require('child_process');
var execFile = cp.execFile;
var fs = require('fs');
var sdc = require('/opt/smartdc/node_modules/sdc-clients');
var vasync =
    require('/opt/smartdc/node_modules/sdc-clients/node_modules/vasync');

var Logger = require('/usr/node/node_modules/bunyan');
var sprintf = require('util').format;

// Globals
var config;
var sdcExtras;
var packages;

var app;
var services;

// XXX TODO:
// parameterize /usbkey prefix (per headnode.sh)

function loadConfig(cb) {
    var log = self.log;
    execFile('/bin/bash', ['/lib/sdc/config.sh', '-json'],
        function _loadConfig(err, stdout, stderr) {
            if (err) {
                log.fatal(err, 'Could not load config: ' + stderr);
                return cb(err);
            }

            try {
                self.config = JSON.parse(stdout);
            } catch (e) {
                log.fatal(e, 'Could not parse config: ' + e.message);
                return cb(e);
            }

            return cb(null);
    });
}

function serviceDomain(service) {
    var cfg = self.config;
    var name = (service === 'manatee' ? 'moray' : service);

    return sprintf('%s.%s.%s', name, cfg.datacenter_name, cfg.dns_domain);
}

// translate config object to SAPI params/metadata.
// currently rolling with everything dropping into metadata, eventually
// I expect some may become params, packages require special handling
// preferably in create_zone.
function translateConfig(cb) {
    var log = self.log;
    var config = self.config;
    self.sdcExtras = {
        metadata: config,
        params: {}
    };
    var sdcExtras = self.sdcExtras;

    if (config.hasOwnProperty('ufds_admin_uuid')) {
        sdcExtras.params.owner_uuid = config.ufds_admin_uuid;
    } else {
        log.warn('No ufds_admin_uuid in config, not setting owner_uuid ' +
                 'in SDC application config.');
    }

    if (! config.hasOwnProperty('binder_admin_ips')) {
        var msg = 'No binder_admin_ips in config, impossible to set up';
        log.fatal(msg);
        return cb(new Error(msg));
    }

    // binder is also zookeeper.
    // bootstrap constraint here: num aligns with ZK_ID of
    if (config.hasOwnProperty('binder_admin_ips')) {
        var binderIps = config.binder_admin_ips.split(',');
        var zkServers = binderIps.map(function (e, i, c) {
            var server = {
                host: e,
                port: 2181,
                num: 1,
                last: true
            };
            if (i == c.length - 1) server.last = true;
            return server;
        });
        sdcExtras.metadata['ZK_SERVERS'] = zkServers;
    }

    sdcExtras.metadata['manatee_shard'] = 'sdc';

    // sapi-url and assets-ip required in customer_metadata, are pushed
    // there from standard metadata by SAPI's payload creation.
    sdcExtras.metadata['sapi-url'] = 'http://' + self.config.sapi_admin_ips;
    sdcExtras.metadata['assets-ip'] = self.config.assets_admin_ip;

    return cb(null);

    // XXX - other things that aren't metadata?
    //     (i.e. metadata of use to *services*?)
    // package definitions - expand them in the services.
    // ?? everything in config.inc/generic?
    // ?? everything that's used purely in setup.
    // exception of sbapi stuff?
    // pkg_*
    // install_agents
    // initial_script
    // utc_offset
    // agents_root
    // zonetracker_database_path
    //
    // generated config:
    // does everything need _root_pw?
    // coal?
    //
    // swap
    // compute_node_swap
    // datacenter_name
    // datacenter_company_name
    // datacenter_loaction
    // default_rack_*
    // default_server_role?
    // admin_nic
    // admin_ip
    // external as well
    // dhcp_range*
    // *shadow
    // phonehome_*
    // show_setup_timers
    // config_inc_dir
}

function addServiceDomains(cb) {
    var dirname = '/usbkey/services';
    var extras = self.sdcExtras;
    var log = self.log;
    fs.readdir(dirname, function (err, services) {
        if (err) {
            log.fatal(err, 'Failed to read %s', dirname);
            return cb(err);
        }
        self.services = services;

        services.forEach(function (service) {
            if (service == 'manatee')
                return;
            var serviceKey = sprintf('%s_SERVICE', service.toUpperCase());
            extras.metadata[serviceKey] = serviceDomain(service);
        });

        return cb(null);
    });
}

// we want an application-level key and fingerprint
function addSigningKey(cb) {
    var log = self.log;
    var extras = self.sdcExtras;
    var keyFile = '/var/ssh/ssh_host_rsa_key.pub';

    async.waterfall([
        function genFingerprint(_cb) {
            var cmd = sprintf('ssh-keygen -lf %s', keyFile);
            cp.exec(cmd, function (err, data) {
                if (err) {
                    log.fatal(err,
                        'Failed to generate fingerprint: %s', err.message);
                    return _cb(err);
                }
                var fingerprint = data.split(' ')[1];
                extras.metadata.ufds_admin_key_fingerprint = fingerprint;
                return _cb(null);
            });
        }, function readKey(_cb) {
            fs.readFile(keyFile, 'utf-8', function (err, data) {
                if (err) {
                    log.fatal(err, 'Failed to read key: %s', err.message);
                    return _cb(err);
                }
                extras.metadata.ufds_admin_key_openssh = data;
                return _cb(null);
            });
        }
    ], function (err) {
        if (err) {
            log.fatal(err, 'Failed to add keys: %s', err.message);
            return cb(err);
        }
        return cb(null);
    });
}

function getPackageInfo(cb) {
    self.packages = Object.keys(self.config).reduce(function (acc, key) {
        if (!key.match('^pkg_'))
             return acc;

        var pkgdata = self.config[key].split(':');
        var pkg = {};
        var obj = {};

        pkg.name = pkgdata[0];
        pkg.ram = pkgdata[1];
        pkg.swap = pkgdata[2];
        pkg.disk = pkgdata[3];
        pkg.cap = pkgdata[4];
        pkg.nlwp = pkgdata[5];
        pkg.iopri = pkgdata[6];
        pkg.uuid = pkgdata[7];

        obj.cpu_shares = Number(pkg.ram); // what MAPI would do.
        obj.cpu_cap = Number(pkg.cap);
        obj.zfs_io_priority = Number(pkg.iopri);
        obj.max_lwps = Number(pkg.nlwp);
        obj.max_physical_memory = Number(pkg.ram);
        obj.max_locked_memory = Number(pkg.ram);
        obj.max_swap = Number(pkg.swap);
        obj.quota = Number(pkg.disk) / 1024; // we want GiB
        obj.quota = obj.quota.toFixed(0); // force Integer
        obj.package_version = '1.0.0';
        obj.package_name = pkg.name;
        obj.billing_id = pkg.uuid;

        acc[pkg.name] = obj;
        return acc;
    }, {});
    return cb(null);
}

function initSapiClient(cb) {
    self.sapi = new sdc.SAPI({
        log: self.log,
        url: 'http://' + self.config.sapi_admin_ips,
        agent: false
    });
    return cb(null);
}

// getOrCreate the SAPI application. NB: if 'get' succeeds, we proceed with
// that metadata.
function getOrCreateSdc(cb) {
    var file = '/usbkey/application.json';
    var log = self.log;
    var ownerUuid = self.config.ufds_admin_uuid;
    var extra = self.sdcExtras;

    log.debug({
        name: 'sdc',
        ownerUuid: ownerUuid,
        file: file,
        extra: extra
    }, 'Creating SDC application');

    self.sapi.getOrCreateApplication('sdc', ownerUuid, file, extra,
        function gotApplication(err, app) {
            if (err) {
                log.fatal(err, 'Could not get/create SDC application: ' +
                    err.message);
                return cb(err);
            }
            log.debug({ sdcApp : app }, 'Created SDC application');
            self.app = app;
            return cb(null);
    });
}

function loadManifests(dirname, cb) {
    var log = self.log;

    self.sapi.loadManifests(dirname, function (err, manifests) {
        if (err) {
            log.fatal(err, 'Could not load manifests: ' +
                      err.message);
            return cb(err);
        }
        log.debug({ manifests: manifests }, 'Created manifests');
        return cb(null, manifests);
    });
}

// check for and add appropriate application manifests.
function createSdcManifests(cb) {
    var manifestDir = '/usbkey/manifests/applications/sdc';

    loadManifests(manifestDir, cb);
}

// We may have retrieved an existing application including manifests;
// we should assume that the existing ones take priority.
function addSdcManifests(manifests, cb) {
    var app = self.app;
    var log = self.log;
    if (!app.hasOwnProperty(manifests)) app.manifests = {};

    Object.keys(manifests).forEach(function (name) {
        if (app.manifests.hasOwnProperty(name)) {
            log.debug('Skipping update of manifest %s', name);
            manifests[name] = app.manifests[name];
        }
    });

    if (Object.getOwnPropertyNames(manifests).length > 0) {
        self.sapi.updateApplication(app.uuid,
            { manifests : manifests }, function (err) {
                if (err) {
                    log.fatal(err, 'Failed to update app: %s', err.message);
                    return cb(err);
                }
                log.debug('Updated application to add manifests');
                return cb(null);
        });
    } else {
        log.debug('No manifests to update');
        return cb(null);
    }

    return (null);
}

// gets the services arranged for creation.
// - loads the package name, adds package information
// - for each service returns an array suitable for function.apply
function prepareServices(cb) {
    var log = self.log;
    var services = self.services;
    var dirname = '/usbkey/services';

    log.debug({ services : services }, 'Creating services.');
    vasync.forEachParallel({
        func: function (service, _cb) {
            // can't believe we need to read a file just for this.
            var file = dirname + '/' + service + '/service.json';
            var extras = { metadata : {}, params : {} };
            var svcDomain = serviceDomain(service);
            extras.metadata['SERVICE_DOMAIN'] = svcDomain;
            var svcDef;
            // XXX - slightly clumsy way to get the package defn.
            // consider moving this to build time?
            fs.readFile(file, function (err, data) {
                if (err) {
                    log.error(err, 'Failed to read %s: %s', file, err.message);
                    return _cb(err);
                }

                try {
                    svcDef = JSON.parse(data);
                } catch (e) {
                    log.error(e, 'Failed to parse %s: %s', file, e.message);
                    return _cb(e);
                }

                if (svcDef.params.hasOwnProperty('package_name')) {
                    extras.params = self.packages[svcDef.params.package_name];
                } else if (svcDef.type === 'agent') {
                    log.info('No package name needed for service of type ' +
                        ' agent: %s', service);
                    extras.type = svcDef.type;
                } else {
                    log.error('No package name for %s', service);
                    return _cb(new Error('No package name for ' + service));
                }

                return _cb(null,
                    [service, self.app.uuid, file, extras, svcDef]);
            });
        },
        inputs: services
    }, function (err, results) {
        if (err) {
            log.fatal(err, 'Failed to create sdc services: %s', err.message);
            return cb(err);
        }

        var serviceList = results.successes;
        log.debug({ services : serviceList }, 'Created services');
        return cb(null, serviceList);
    });
}

// Adds user-script, other required customer-metadata, performs service-specific
// adjustments.
// serviceList is [service, self.app.uuid, file, extras]
function filterServices(serviceList, cb) {
    var log = self.log;
    fs.readFile('/usbkey/default/user-script.common', function (err, data) {
        if (err) {
            log.fatal(err, 'Could not read user script: %s', err.message);
            return cb(err);
        }

        var list = serviceList.map(function (serviceArgs) {
            var service = serviceArgs[0];
            var extras = serviceArgs[3];
            var svcDef = serviceArgs[4];

            assert.ok(serviceArgs.length === 5);
            assert.string(service, 'service');
            assert.object(extras, 'extras');
            assert.object(svcDef, 'svcDef');

            // papi needs package defn's.
            if (service == 'papi') {
                packages = Object.keys(self.config).reduce(function (acc, key) {
                    if (key.match('^pkg_')) acc.push(self.config[key]);
                    return acc;
                }, []);

                extras.metadata['packages'] = packages.join('\n');
            }

            // napi needs resolvers in metadata
            if (service == 'napi') {
                extras.metadata['admin_resolvers'] =
                JSON.stringify(self.config.binder_admin_ips.split(','));
                extras.metadata['ext_resolvers'] =
                JSON.stringify(self.config.dns_resolvers.split(','));
            }

            // The CloudAPI service's plugins each need the datacenter name
            if (service === 'cloudapi') {
                var datacenter = self.config.datacenter_name;
                var plugins = svcDef.metadata['CLOUDAPI_PLUGINS'];

                plugins.forEach(function (plugin) {
                    if (plugin.config)
                        plugin.config.datacenter = datacenter;
                });

                extras.metadata['CLOUDAPI_PLUGINS'] = JSON.stringify(plugins);

                extras.metadata['CLOUDAPI_DATACENTERS'] = {};
                extras.metadata['CLOUDAPI_DATACENTERS'][datacenter] =
                    'https://' + self.app.metadata['CLOUDAPI_SERVICE'];
                extras.metadata['CLOUDAPI_DATACENTERS'] =
                    JSON.stringify(extras.metadata['CLOUDAPI_DATACENTERS']);
            }

            // *everything* needs customer_metadata
            if (!extras.params.hasOwnProperty('customer_metadata')) {
                extras.params['customer_metadata'] = {};
            }

            extras.metadata['sapi-url'] =
                'http://' + self.config.sapi_admin_ips;
            extras.metadata['assets-ip'] = self.config.assets_admin_ip;
            extras.metadata['user-script'] = data.toString();

            // There's no need to pass the service defintion to
            // getOrCreateService() below, so remove it.
            serviceArgs.pop();

            return serviceArgs;
        });

        log.debug({serviceList : list}, 'Adjusted service definitions');

        return cb(null, list);
    });
}

function getOrCreateServices(serviceList, cb) {
    var log = self.log;
    vasync.forEachParallel({
        func: function (serviceArgs, _cb) {
            var f = self.sapi.getOrCreateService;
            f.apply(self.sapi, serviceArgs.concat(_cb));
        },
        inputs: serviceList
    }, function (err, results) {
        if (err) {
            log.fatal(err, 'Failed to create SDC services: %s', err.message);
            return cb(err);
        }
        self.services = results.successes;
        log.debug({ services : self.services }, 'Created SDC servces');
        return cb(null, self.services);
    });
}

/* -- Mainline -- */

var self = this;
self.log = new Logger({
    name: 'sdc-init',
    level: 'trace',
    serializers: Logger.stdSerializers
});

async.waterfall([
    loadConfig,
    translateConfig,
    addServiceDomains,
    addSigningKey,
    getPackageInfo,
    initSapiClient,
    getOrCreateSdc,
    createSdcManifests,
    addSdcManifests,
    prepareServices,
    filterServices,
    getOrCreateServices
], function (err) {
    if (err) {
        console.error('Error: ' + err.message);
        process.exit(1);
    }
    process.exit(0);
});
