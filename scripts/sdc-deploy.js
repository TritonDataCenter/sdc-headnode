#!/usr/node/bin/node

/*
 * Copyright (c) 2013, Joyent, Inc. All rights reserved.
 *
 * sdc-init-app.js: initializes sdc SAPI application definition.
 */

var async = require('/usr/node/node_modules/async');
var sdc = require('/opt/smartdc/node_modules/sdc-clients');
var Logger = require('/usr/node/node_modules/bunyan');
var cp = require('child_process');
var execFile = cp.execFile;
var fs = require('fs');

// Globals
var sapiUrl = process.argv[2];
var zone = process.argv[3];
var passed_uuid = process.argv[4];
var config;

// needed for nics, atm.
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

function initSapiClient(cb) {
    self.sapi = new sdc.SAPI({
        log: self.log,
        url: sapiUrl,
        agent: false
    });
    return cb(null);
}

function getService(cb) {
    var log = self.log;
    self.sapi.listServices({
        name: zone
    }, function(err, services) {
        if (err) {
            log.fatal(err, 'Could not find service for %s', zone);
            return cb(err);
        }
        // XXX assuming unambiguous search.
        return cb(null, services[0]);
    });
}

function createInstance(service, cb) {
    var log = self.log;
    var opts = { params: {}, metadata : {} };
    opts.uuid = passed_uuid;
    opts.params.alias = zone + '0';
    if (process.env['UPGRADING']) {
        opts.metadata['IS_UPDATE'] = '1';
    }
    if (process.env['ONE_NODE_WRITE_MODE']) {
        opts.metadata['ONE_NODE_WRITE_MODE'] = 'true';
    }
    self.sapi.createInstance(service.uuid, opts, function(err, instance) {
        if (err) {
            log.fatal(err, 'Could not create instance for %s', service.name);
            return cb(err);
        }
        // log.debug({ instance: instance }, 'Created instance %s', instance.uuid);
        return cb(null, instance)
    });
}

function getPayload(instance, cb) {
    var log = self.log;
    self.sapi.getInstancePayload(instance.uuid, function(err, payload) {
        if (err) {
            log.fatal(err, 'Could not get payload for instance %s', instance.uuid);
            return cb(err);
        }
        // log.debug('Found payload for instance %s', instance.uuid);
        return cb(null, payload);
    });
}

// nics per build-payload
function addNic(payload, cb) {
    if (payload.hasOwnProperty('nics')) {
        return cb(null, payload);
    }
    var config = self.config;
    var nic = {};
    payload.nics = [nic];

    nic.ip = config[zone + '_admin_ips'].split(',')[0];
    if (config.hasOwnProperty('admin_netmask')) {
        nic.netmask = config.admin_netmask;
    } else {
        nic.netmask = '255.255.255.0';
    }
    nic.nic_tag = 'admin';
    nic.vlan_id = 0;
    nic.interface = 'net0';
    nic.primary = true;

    if (zone == "dhcpd") {
        nic.dhcp_server = true;
    }

    return cb(null, payload);
}

function addUserScript(payload, cb) {
    fs.readFile('/usbkey/default/user-script.common', function(err, data) {
        var customer_metadata;

        if (err) {
            log.fatal(err, 'Could not read user script: ', + err.message);
            return cb(err);
        }

        if (!payload.hasOwnProperty('customer_metadata')) {
            payload.customer_metadata = {};
        }
        payload.customer_metadata['sapi-service'] = "true";
        payload.customer_metadata['user-script'] = data.toString();
        payload.customer_metadata['assets-ip'] = self.config.assets_admin_ip;
        payload.customer_metadata['sapi-url'] = 'http://' + self.config.sapi_admin_ips;
        return cb(null, payload);
    });
}

function outputPayload(payload, cb) {
    // also add the uuid if any.
    if (passed_uuid && passed_uuid.length > 0) {
        payload.uuid = passed_uuid;
    }
    console.log(JSON.stringify(payload, null, 2));
    return cb(null);
}

/* -- Mainline -- */

if (!passed_uuid) {
    self.log.fatal('No uuid passed to sdc-deploy');
    process.exit(1);
}

var self = this;
self.log = new Logger({
    name: 'sdc-deploy',
    level: 'debug',
    serializers: Logger.stdSerializers
});

async.waterfall([
    loadConfig,
    initSapiClient,
    getService,
    createInstance,
    getPayload,
    addNic,
    addUserScript,
    outputPayload
], function (err) {
    if (err) {
        self.log.fatal('Failed to deploy %s', zone);
        process.exit(1);
    }
    process.exit(0);
});
