#!/usr/node/bin/node

/*
 * Copyright (c) 2013, Joyent, Inc. All rights reserved.
 *
 * sdc-init-app.js: initializes sdc SAPI application definition.
 */

var async = require('/usr/node/node_modules/async');
var vasync = require('/opt/smartdc/node_modules/sdc-clients/node_modules/vasync');
var cp = require('child_process');
var execFile = cp.execFile;
var fs = require('fs');
var sdc = require('/opt/smartdc/node_modules/sdc-clients');
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
                log.fatal(e, 'Could not parse config: ' + e.message)
                return cb(e);
            }

            return cb(null);
        }
    );
}

function serviceName(service) {
    var cfg = self.config;
    var name = (service === "manatee" ? "moray" : service);

    return sprintf("%s.%s.%s", name, cfg.datacenter_name, cfg.dns_domain);
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
    }
    var sdcExtras = self.sdcExtras;
    var resolvers = [];


    if (config.hasOwnProperty('ufds_admin_uuid')) {
        sdcExtras.params.owner_uuid = config.ufds_admin_uuid;
    } else {
        log.warn('No ufds_admin_uuid in config, not setting owner_uuid ' +
                 'in SDC application config.');
    }

    // XXX NET-207, HEAD-1466 may have something to say about the following:
    if (config.hasOwnProperty('binder_resolver_ips')) {
        resolvers = resolvers.concat(config.binder_resolver_ips.split(','));
    } else {
        var msg = 'No binder_resolver_ips in config, impossible to set up';
        log.fatal(msg);
        return cb(new Error(msg));
    }

    if (config.hasOwnProperty('dns_resolvers')) {
        resolvers = resolvers.concat(config.dns_resolvers.split(','));
    }

    if (resolvers.length > 0) {
        sdcExtras.params.resolvers = resolvers;
    }

    // binder is also zookeeper.
    if (config.hasOwnProperty('binder_admin_ips')) {
        var binderIps = config.binder_admin_ips.split(',');
        var zkServers = binderIps.map(function(e, i, c) {
            var server = {
                host: e,
                port: 2181
            };
            if (i == c.length - 1) server.last = true;
            return server;
        });
        sdcExtras.metadata['ZK_SERVERS'] = zkServers;
    }

    sdcExtras.metadata['manatee_shard'] = 'sdc';

    return cb(null);

    // XXX - other things that aren't metadata? i.e. metadata of use to *services*?
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
    // serialize_setup
    // config_inc_dir
}

function addServiceNames(cb) {
    var dirname = '/usbkey/services';
    var extras = self.sdcExtras;
    var log = self.log;
    fs.readdir(dirname, function(err, services) {
        if (err) {
            log.fatal(err, 'Failed to read %s', dirname);
            return cb(err);
        }
        self.services = services;

        services.forEach(function(service) {
            if (service == "manatee") return;
            var serviceKey = sprintf("%s_SERVICE", service.toUpperCase());
            extras.metadata[serviceKey] = serviceName(service);
        });

        return cb(null)
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
            cp.exec(cmd, function(err, data) {
                if (err) {
                    log.fatal(err, 'Failed to generate fingerprint: %s', err.message);
                    return _cb(err);
                }
                var fingerprint = data.split(' ')[0];
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
    ], function(err) {
        if (err) {
            log.fatal(err, "Failed to add keys: %s", err.message);
            return cb(err);
        }
        return cb(null);
    });
}

function getPackageInfo(cb) {
    self.packages = Object.keys(self.config).reduce(function(acc, key) {
        if (!key.match('^pkg_')) return acc;

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
    var ownerUuid = self.config.ufds_admin_uuid
    var extra = self.sdcExtras;

    log.debug({name : 'sdc', ownerUuid : ownerUuid, file : file, extra : extra}, 'Creating SDC application');

    self.sapi.getOrCreateApplication('sdc', ownerUuid, file, extra,
        function gotApplication(err, app) {
            if (err) {
                log.fatal(err, 'Could not get/create SDC application: ' + err.message);
                return cb(err);
            }
            log.debug({ sdcApp : app }, 'Created SDC application');
            self.app = app;
            return cb(null);
        }
    );
}

function loadManifests(dirname, cb) {
    var log = self.log;

    self.sapi.loadManifests(dirname, function(err, manifests) {
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

    Object.keys(manifests).forEach(function(name) {
        if (app.manifests.hasOwnProperty(name)) {
            log.debug('Skipping update of manifest %s', name);
            manifests[name] = app.manifests[name];
        }
    });

    if (Object.getOwnPropertyNames(manifests).length > 0) {
        self.sapi.updateApplication(app.uuid,
            { manifests : manifests }, function(err) {
                if (err) {
                    log.fatal(err, 'Failed to update app: %s', err.message);
                    return cb(err);
                }
                log.debug('Updated application to add manifests');
                return cb(null);
            }
        );
    } else {
        log.debug('No manifests to update');
        return cb(null);
    }
}

// gets the services arranged for creation.
// - loads the package name, adds package information
// - for each service returns an array suitable for function.apply
function prepareServices(cb) {
    var log = self.log;
    var services = self.services;
    var dirname = '/usbkey/services';

    log.debug({ services : services }, "Creating services.");
    vasync.forEachParallel({
        func: function(service, _cb) {
            // can't believe we need to read a file just for this.
            var file = dirname + '/' + service + '/service.json';
            var svcName = serviceName(service);
            var extras = { metadata : {}, params : {} };
            extras.metadata['SERVICE_NAME'] = svcName;
            var svcDef;
            // XXX - slightly clumsy way to get the package defn.
            // consider moving this to build time?
            fs.readFile(file, function(err, data) {
                if (err) {
                    log.error(err, 'Failed to read %s: %s', file, err.message);
                    return _cb(err);
                }

                try {
                    svcDef = JSON.parse(data);
                } catch(e) {
                    log.error(e, 'Failed to parse %s: %s', file, e.message);
                    return _cb(e);
                }

                if (svcDef.params.hasOwnProperty('package_name')) {
                    extras.params = self.packages[svcDef.params.package_name];
                } else {
                    log.error('No package name for %s', service);
                    return _cb(new Error('No package name for ' + service));
                }

                return _cb(null, [service, self.app.uuid, file, extras]);
            });
        },
        inputs: services
    }, function (err, results) {
        if (err) {
            log.fatal(err, 'Failed to create sdc services: %s', err.message);
            return cb(err);
        }

        serviceList = results.successes;
        log.debug({ services : serviceList }, 'Created services');
        return cb(null, serviceList);
    });
}

// Adds user-script, other required customer-metadata, performs service-specific
// adjustments.
// serviceList is [service, self.app.uuid, file, extras]
function filterServices(serviceList, cb) {
    var log = self.log;
    fs.readFile('/usbkey/default/user-script.common', function(err, data) {
        if (err) {
            log.fatal(err, 'Could not read user script: %s', err.message);
            return cb(err);
        }

        var list = serviceList.map(function(serviceArgs) {
            var service = serviceArgs[0];
            var extras = serviceArgs[3];

            // ufds needs package defn's.
            if (service == 'ufds') {
                packages = Object.keys(self.config).reduce(function(acc, key) {
                    if (key.match('^pkg_')) acc.push(self.config[key]);
                    return acc;
                }, []);

                extras.metadata['packages'] = packages.join('\n');
            }

            // napi needs resolvers in metadata
            if (service == 'napi') {
                extras.metadata['resolvers'] =
                JSON.stringify(self.config.dns_resolvers.split(','));
            }

            // *everything* needs customer_metadata
            if (!extras.params.hasOwnProperty('customer_metadata')) {
                extras.params['customer_metadata'] = {};
            }

            // customer_metadata overwritten.
            // extras.params['customer_metadata']['assets-ip'] =
            //     self.config.assets_admin_ip;
            // extras.params['customer_metadata']['sapi-url'] =
            //     'http://' + self.config.sapi_admin_ips;
            // extras.params['customer_metadata']['sapi-service'] = "true";
            // extras.params['customer_metadata']['user-script'] = data.toString();
            extras.metadata['sapi-url'] = 'http://' + self.config.sapi_admin_ips;
            extras.metadata['assets-ip'] = self.config.assets_admin_ip;
            extras.metadata['user-script'] = data.toString();
            return serviceArgs;
        });

        log.debug({serviceList : list}, 'Adjusted service definitions');

        return cb(null, list);
    });
}

function getOrCreateServices(serviceList, cb) {
    var log = self.log;
    vasync.forEachParallel({
        func: function(serviceArgs, _cb) {
            var f = self.sapi.getOrCreateService;
            f.apply(self.sapi, serviceArgs.concat(_cb));
        },
        inputs: serviceList
    }, function(err, results) {
        if (err) {
            log.fatal(err, 'Failed to create SDC services: %s', err.message);
            return cb(err);
        }
        self.services = results.successes;
        log.debug({ services : self.services }, 'Created SDC servces');
        return cb(null, self.services);
    });
}

// each service should have a corresponding directory:
// /usbkey/manifests/services/SERVICE/MANIFEST_NAME/[manifest.json, template]
function createSvcManifests(services, cb) {
    var dirname = '/usbkey/manifests/services';
    var log = self.log;
    var results;

    vasync.forEachParallel({
        func: function(service, _cb) {
            var dir = dirname + '/' + service;
            loadManifests(dir, function(err, manifests) {
                if (err) {
                    return _cb(err);
                }
                log.debug({ manifests : manifests }, 'Found manifests for %s', service)
                var result = {};
                result[service] = manifests;
                return _cb(null, result)
            });
        },
        inputs: services.map(function(srvc) { return srvc.name })
    }, function (err, manifests) {
        // what does this look like anyway?
        if (err) {
            log.fatal(err, 'Failed to create sdc services: %s', err.message);
            return cb(err);
        }

        results = manifests.successes.reduce(function(acc, manifest) {
            Object.keys(manifest).forEach(function(svc) {
                acc[svc] = manifest[svc];
            })
            return acc;
        }, {});

        log.debug({ svc_manifests : results }, 'created svc manifests');
        return cb(null, results);
    });
}

function addSvcManifests(manifests, cb) {
    var log = self.log;

    vasync.forEachParallel({
        func: function(service, _cb) {
            var svcManifests = manifests[service.name];

            if (!service.hasOwnProperty(manifests)) service.manifests = {};

            Object.keys(manifests).forEach(function(name) {
                if (service.manifests.hasOwnProperty(name)) {
                    log.debug('Skipping update of exostomg %s manifest %s', service.name, name);
                    svcManifests[name] = service.manifests[name];
                }
            });

            if (Object.getOwnPropertyNames(svcManifests).length > 0) {
                self.sapi.updateService(service.uuid,
                    { manifests : svcManifests }, function(err) {
                    if (err) {
                        log.fatal(err, 'Failed to update %s: %s', service.name, err.message);
                        return _cb(err);
                    }
                    log.debug('Updated %s with manifests', service.name);
                    return _cb(null);
                });
            } else {
                log.debug('No manifests to update for %s', service.name);
                return _cb(null);
            }
        },
        inputs: self.services
    }, function(err, services) {
        if (err) {
            log.fatal(err, 'Failed to add manifests to all services: %s', err.message);
            return cb(err);
        }
        log.debug('All service manifests added.');
        return cb(null);
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
    addServiceNames,
    addSigningKey,
    getPackageInfo,
    initSapiClient,
    getOrCreateSdc,
    createSdcManifests,
    addSdcManifests,
    prepareServices,
    filterServices,
    getOrCreateServices,
    createSvcManifests,
    addSvcManifests
], function(err) {
    if (err) {
        console.error("Error: " + err.message);
        process.exit(1);
    }
    process.exit(0);
});
