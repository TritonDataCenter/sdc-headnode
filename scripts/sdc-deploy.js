#!/usr/node/bin/node
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2018, Joyent, Inc.
 */

var async = require('/usr/node/node_modules/async');
var sdc = require('/opt/smartdc/node_modules/sdc-clients');
var Logger = require('/usr/node/node_modules/bunyan');
var cp = require('child_process');
var execFile = cp.execFile;
var fs = require('fs');



// ---- globals

var log;
var config;
var sapi;



// ---- support functions

// needed for nics, atm.
function loadConfig(cb) {
    execFile('/bin/bash', ['/lib/sdc/config.sh', '-json'],
        function _loadConfig(err, stdout, stderr) {
            if (err) {
                log.fatal(err, 'Could not load config: ' + stderr);
                return cb(err);
            }

            try {
                config = JSON.parse(stdout); // intentionally global
            } catch (e) {
                log.fatal(e, 'Could not parse config: ' + e.message);
                return cb(e);
            }

            return cb(null);
        });
}

function initSapiClient(cb) {
    sapi = new sdc.SAPI({ // intentionally global
        log: log,
        url: sapiUrl,
        version: '~2',
        agent: false
    });
    return cb(null);
}

function getService(cb) {
    sapi.listServices({
        name: zone
    }, function withServices(err, services) {
        if (err) {
            log.fatal(err, 'Could not find service for %s', zone);
            return cb(err);
        }
        log.info({services: services}, 'got service');
        // XXX assuming unambiguous search.
        return cb(null, services[0]);
    });
}

function createInstance(service, cb) {
    var opts = { params: {}, metadata : {} };
    opts.uuid = passed_uuid;
    opts.params.alias = zone + '0';
    if (process.env['ONE_NODE_WRITE_MODE']) {
        opts.metadata['ONE_NODE_WRITE_MODE'] = 'true';
    }

    if (service.name == 'binder') {
        opts.metadata['ZK_ID'] = 1;
    }


    sapi.createInstance(service.uuid, opts, function withInsts(err, instance) {
        if (err) {
            log.fatal(err, 'Could not create instance for %s', service.name);
            return cb(err);
        }
        return cb(null, instance);
    });
}

function getPayload(instance, cb) {
    sapi.getInstancePayload(instance.uuid, function withPayload(err, payload) {
        if (err) {
            log.fatal(err, 'Could not get payload for instance %s',
                      instance.uuid);
            return cb(err);
        }
        // log.debug('Found payload for instance %s', instance.uuid);
        return cb(null, payload);
    });
}

function addResolvers(payload, cb) {
    if (payload.hasOwnProperty('resolvers')) {
        return cb(null, payload);
    }

    payload.resolvers = config['binder_admin_ips'].split(',');
    return cb(null, payload);
}

// nics per build-payload
function addNic(payload, cb) {
    if (payload.hasOwnProperty('nics')) {
        return cb(null, payload);
    }
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

    if (zone == 'dhcpd') {
        nic.dhcp_server = true;
    }

    return cb(null, payload);
}

function outputPayload(payload, cb) {
    // also add the uuid if any.
    if (passed_uuid && passed_uuid.length > 0) {
        payload.uuid = passed_uuid;
    }
    console.log(JSON.stringify(payload, null, 2));
    return cb(null);
}



// ---- mainline

var sapiUrl = process.argv[2];
var zone = process.argv[3];

log = new Logger({
    name: 'sdc-deploy',
    level: 'debug',
    serializers: Logger.stdSerializers,
    stream: process.stderr,
    zone: zone
});

var passed_uuid = process.argv[4];
if (!passed_uuid) {
    log.fatal('No uuid passed to sdc-deploy');
    process.exit(1);
}


async.waterfall([
    loadConfig,
    initSapiClient,
    getService,
    createInstance,
    getPayload,
    addResolvers,
    addNic,
    outputPayload
], function (err) {
    if (err) {
        log.fatal('Failed to deploy %s', zone);
        process.exit(1);
    }
    process.exit(0);
});
