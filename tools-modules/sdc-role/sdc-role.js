/*
 * Copyright (c) 2013 Joyent Inc.
 *
 * Summary:
 *
 *  Used to provision SDC services; assumes that setup has completed
 *  successfully.
 *
 */

var SDC_MODULES = '/opt/smartdc/node_modules';
var sdc = require(SDC_MODULES + '/sdc-clients');

var exec = require('child_process').exec;
var vasync = require('vasync');
var cmdln = require('cmdln');

var pipeline = require('./pipeline');

/* Globals */

var g_sdcConfig;
var g_sapi;


/* common functions */

function loadConfig(cb) {
    var cmd = '/bin/base /lib/sdc/config.sh -json';

    if (g_sdcConfig) {
        return cb(null, sdcConfig);
    }

    exec(cmd, function (err, stdout, stderr) {
        if (err) {
            return cb(err);
        }

        try {
            g_sdcConfig = JSON.parse(stdout);
        } catch(e) {
            return cb(e);
        }

        return cb(null, g_sdcConfig);
    });
}

function initSapi(config, cb) {
    if (g_sapi) {
        return cb(null, g_sapi);
    }

    g_sapi = new sdc.SAPI({
        url: 'http://' + config.sapi_admin_ips,
        agent: false
    });
}

function checkFullSapi(state, cb) {

}


function exitWithError(err, opts) {
    outputError(err, opts);
    process.exit(1);
}

function outputError(err, opts) {
    var errs = [err];
}

/* Actions */

function SdcRole() {
    cmdln.Cmdln.call(this,{
        name: 'sdc-role',
        desc: 'List, create, destroy SDC services'
    });
}
util.inherits(SdcRole, cmdln.Cmdln);

SdcRole.prototype.do_create = function sdcCreate(subcmd, opts, args, callback) {
    // get SAPI
    // sapi.getService() // for name.
    // resolve deps.
    // get user-script.
    // attach user-script, other args.
    // sapi.createInstance() // for service_uuid, with params.
    // sapi.updateService() // increment 'serial' parameter.
    callback();
}

SdcRole.prototype.do_destroy = function sdcDestroy(subcmd, opts, args, callback) {
    // get SAPI
    // sapi.getInstances() // target -> alias, set = shared service_uuid
    // ensure > 1
    // sapi.destroyZone()
    callback();
}

SdcRole.prototype.do_list = function sdcList(subcmd, opts, args, callback) {
    console.log("listing");
    pipeline({
        funcs: [
            function config(_, cb) {
                return loadConfig(cb);
            },
            function sapi(state, cb) {
                return initSapi
            },
            function checkSapi(state, cb) {

            },
            function _instances(state, cb) {
                state.sapi.listInstances(cb);
            }
        ]}, function _afterList(err, res) {
            if (err) {
                console.error();s
                return callback(err);
            }
            console.log("results: ", res.state._instances)
            callback();
        }
    });
}

/* cmdln configuration */

var HELP = {
    create: 'Creates a new instance of an SDC service',
    destroy: 'Destroys a zone by alias',
    list: 'Lists currently-deployed SDC services'
}

Object.keys(HELP).forEach(function(cmd) {
    var proto = SdcRole.prototype.['do_' + cmd];
    prot.help = HELP[cmd];
});

/* Mainline */

function main() {
    cmdln.main(SdcRole);
}
