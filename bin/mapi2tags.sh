#!/usr/bin/env node
// -*- mode: js -*-

// Copyright (c) 2013, Joyent, Inc., All rights reserved.
// Export tag data from MAPI PostgreSQL dump

var fs = require('fs');
var path = require('path');
var util = require('util');
// Using Spanish here to avoid having to change all the "exists" references:
var existe = fs.exists || path.exists;
var existsSync = fs.existsSync || path.existsSync;


///--- Globals

var directory;  // set in `process_argv()`.

var Types = ['vms', 'zones'];

var NULL = '\\N';

// position of the uuid - number of columns
var UUID_POSITIONS = {
    'zones': [1, 45],
    'vms': [1, 30]
};

var TAGS, VMS, ZONES;

///--- Helpers
// NOTE: Shamelessly copying from capi2lidf.sh, maybe should consider sharing?.

function err_and_exit() {
    console.error.apply(arguments);
    process.exit(1);
}


function usage(msg, code) {
    if (typeof(msg) === 'string') {
        console.error(msg);
    }

    console.error('%s <directory>',
        path.basename(process.argv[1]));
    process.exit(code || 0);
}



function process_argv() {
    if (process.argv.length !== 3) {
        usage(null, 1);
    }

    try {
        var stats = fs.statSync(process.argv[2]);
        if (!stats.isDirectory()) {
            usage(process.argv[2] + ' is not a directory', 1);
        }
    } catch (e) {
        usage(process.argv[2] + ' is invalid: ' + e.toString(), 1);
    }

    directory = process.argv[2];
}



function read_lines(file, callback) {
    return fs.readFile(file, 'utf8', function(err, data) {
        if (err) {
            return callback(err);
        }

        return callback(null, data.split('\n'));
    });
}



function read_lines_sync(file) {
    try {
        var data = fs.readFileSync(file, 'utf8');
        return data.split('\n');
    } catch (err) {
        return err_and_exit('Error loading '+ file + ': %s', err.toString());
    }
}


// Real stuff goes here:

// This function will read a table and create a mapping between
// row ids and uuids like
//
// { '1': { uuid: <uuid> } }
//
function transform_vm_uuids(table) {
    var util = require('util');

    var file = directory + '/' + table + '.dump';
    var lines = read_lines_sync(file);
    var hash = {};
    var total = lines.length;
    var uuid = UUID_POSITIONS[table][0];
    var columns = UUID_POSITIONS[table][1];

    lines.forEach(function(line) {
        var pieces = line.split('\t');
        if (pieces.length < columns) {
            return;
        }

        hash[pieces[0]] = {
            uuid: pieces[uuid]
        };
    });

    return hash;
}


// This function will read the tags table and create a mapping between
// machine ids and tag key/values like:
//
// {
//   "zones": {'1': { key: value, foo: bar } },
//   "vms": {'3': { bar: baz } }
// }
//
// Since tags can belong to zones and vms, the hash is provided in this form.
function transform_tags(table) {
    var util = require('util');

    var file = directory + '/' + table + '.dump';
    var lines = read_lines_sync(file);
    var hash = { "Zone": {}, "VM": {} };
    var total = lines.length;

    var TAG_KEY = 1;
    var TAG_VALUE = 2;
    var TAGGABLE_ID = 3;
    var TAGGABLE_TYPE = 4;
    var columns = 7;

    lines.forEach(function(line) {
        var pieces = line.split('\t');
        if (pieces.length < columns) {
            return;
        }

        var obj = hash[ pieces[TAGGABLE_TYPE] ][ pieces[TAGGABLE_ID] ];

        if (!obj)
            obj = {};

        obj[pieces[TAG_KEY]] = pieces[TAG_VALUE];
        hash[ pieces[TAGGABLE_TYPE] ][ pieces[TAGGABLE_ID] ] = obj;
    });

    return hash;
}

function transform_vms(file, callback) {
    if (can_transform_vms() === false) {
        return callback();
    }

    var util = require('util');
    var table = (file.indexOf('vms') !== -1) ? 'vms': 'zones';

    return read_lines(file, function(err, lines) {
        if (err) {
          return err_and_exit('Error loading vms file: %s', err.toString());
        }

        var changes = [];
        var total = lines.length;

        lines.forEach(function(line) {
            var pieces = line.split('\t'), uuid;

            if (pieces.length == 45) {
                vm_from_zone(pieces);
            } else if (pieces.length == 30) {
                vm_from_vm(pieces);
            }
        });

        callback();
    });
}

function vm_from_vm(pieces) {
    // if destroyed, skip it
    if (pieces[8] !== '\\N')
        return;

    var tags = TAGS['VM'][ pieces[0] ];
    if (tags) {
        console.log(pieces[1] + ' ' + JSON.stringify(tags));
    }
}

function vm_from_zone(pieces) {
    // if destroyed, skip it
    if (pieces[8] !== '\\N')
        return;

    var tags = TAGS['Zone'][ pieces[0] ];
    if (tags) {
        console.log(pieces[1] + ' ' + JSON.stringify(tags));
    }
}


///--- Mainline

process_argv();

// We do this here because the other transform function will need these
// values
VMS = transform_vm_uuids('vms');
ZONES = transform_vm_uuids('zones');

function can_transform_vms() {
    var file;

    file = directory + '/tags.dump';
    if (!existsSync(file)) {
        return false;
    }

    // Try loading this when paths exist
    TAGS = transform_tags('tags');
    return true;
}


var cur;
var types = [
    ['vms', transform_vms ],
    ['zones', transform_vms ]
];

function processNextDump(err) {
    if (err) {
        if (err.length) {
            console.error('Errors importing "%s":', cur[0]);
            err.forEach(function (e) {
                console.error('  ' + e.message);
            });
        } else {
            console.error('Error importing "%s": %s', cur[0], err.message);
        }
        process.exit(1);
    }

    cur = types.shift();
    if (!cur) {
        return;
    }
    var file = directory + '/' + cur[0] + '.dump';
    existe(file, function (exists) {
        if (!exists) {
            console.error('Dump file does not exist: %s', file);
            process.exit(1);
        }

        process.nextTick(function () {
            cur[1](file, processNextDump);
        });
    });
}

processNextDump();
