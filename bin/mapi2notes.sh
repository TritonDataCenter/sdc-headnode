#!/usr/bin/env node
// -*- mode: js -*-
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

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
    'servers': [16, 29],
    'zones': [1, 45],
    'vms': [1, 30]
};

var SERVERS, VMS, ZONES;

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
function transform_uuids(table) {
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


// This function will read the comments table and create an object like:
//      {
//          item_uuid: {server/zone/vm uuid},
//          owner_uuid: pieces[4],
//          note: pieces[1],
//          created: pieces[5]
//      }
//
function transform_comments(file) {
    var util = require('util');

    var lines = read_lines_sync(file);

    lines.forEach(function(line) {
        var pieces = line.split('\t');

        if (pieces.length != 7)
            return;

        var uuid;
        if (pieces[3] === "Server") {
            uuid = SERVERS[pieces[2]].uuid;
        } else if (pieces[3] === "Zone") {
            uuid = ZONES[pieces[2]].uuid;
        } else {
            uuid = VMS[pieces[2]].uuid;
        }

        var note = {
            item_uuid: uuid,
            owner_uuid: pieces[4],
            note: pieces[1],
            created: pieces[5]
        };

        console.log(JSON.stringify(note));
    });
}

///--- Mainline

process_argv();

// We do this here because the other transform function will need these
// values
SERVERS = transform_uuids('servers');
VMS = transform_uuids('vms');
ZONES = transform_uuids('zones');

function processCommentDump(err) {
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

    var file = directory + '/comments.dump';
    existe(file, function (exists) {
        if (!exists) {
            console.error('Dump file does not exist: %s', file);
            process.exit(1);
        }

        transform_comments(file);
    });
}

processCommentDump();
