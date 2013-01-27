#!/usr/bin/env node
// -*- mode: js -*-

// Copyright (c) 2012, Joyent, Inc., All rights reserved.
// Export data from MAPI PostgreSQL dump to be imported by UFDS into LDAP.

var fs = require('fs');
var path = require('path');
var util = require('util');



///--- Globals

var Types = ['vms', 'zones', 'servers'];

// position of the uuid - number of columns
var UUID_POSITIONS = {
    'servers': [16, 29],
    'datasets': [4, 28],
    'zfs_storage_pools': [1, 11]
};

var SERVERS, IMAGES, ZPOOLS;


///--- Helpers
// NOTE: Seamlessly copying from capi2lidf.sh, maybe should consider sharing?.

function err_and_exit() {
    console.error.apply(arguments);
    process.exit(1);
}


// The datacenter name is stored in the config file, not in mapi.
// Pass in the datacenter name as an argument.
function usage(msg, code) {
    if (typeof(msg) === 'string') {
        console.error(msg);
    }


    console.error('%s <directory> <dcname>', path.basename(process.argv[1]));
    process.exit(code || 0);
}



function process_argv() {
    if (process.argv.length < 4) {
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
    datacenter = process.argv[3];
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
// { '1': <uuid> }
//
// Then on a table like zones we are table to replace server_id with
// the corresponding server_uuid
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

        hash[pieces[0]] = pieces[uuid];
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

        if (!obj) {
            obj = [];
        }

        obj.push( pieces[TAG_KEY] + '=' + pieces[TAG_VALUE] );
        hash[ pieces[TAGGABLE_TYPE] ][ pieces[TAGGABLE_ID] ] = obj;
    });

    return hash;
}



function transform_vms(file, callback) {
    var util = require('util');

    return read_lines(file, function(err, lines) {
        if (err) {
          return err_and_exit('Error loading vms file: %s', err.toString());
        }

        var changes = [];
        var total = lines.length;

        // How to access these values?
        //
        //     datasets
        //     nics
        //     delegate_dataset
        lines.forEach(function(line) {
            var change;
            var pieces = line.split('\t'), uuid;

            if (pieces.length == 45) {
                change = vm_from_zone(pieces);
            } else if (pieces.length == 30) {
                change = vm_from_vm(pieces);
            } else {
                return;
            }

            changes.push(change);
        });

        return callback(changes);
    });
}

/**
 * 0 -- id
 * 1 -- name
 * 2 -- alias
 * 3 -- owner_uuid
 * 4 -- dataset_id
 * 5 -- server_id
 * 6 -- deactivated_at
 * 7 -- deactivated_by
 * 8 -- destroyed_at
 * 9 -- destroyed_by
 * 10 -- created_at
 * 11 -- updated_at
 * 12 -- creation_state
 * 13 -- swap
 * 14 -- customer_metadata
 * 15 -- internal_metadata
 * 16 -- ram
 * 17 -- customer_assigned_at
 * 18 -- zfs_io_priority
 * 19 -- cpu_cap
 * 20 -- cpu_shares
 * 21 -- lightweight_processes
 * 22 -- disk
 * 23 -- setup_at
 * 24 -- setup_by
 * 25 -- disks
 * 26 -- zfs_storage_pool_id
 * 27 -- primary_network_id
 * 28 -- vcpus
 * 29 -- latest_heartbeat_cache
 */
function vm_from_vm(pieces) {
    var change;
    var created_at = (pieces[23] == '\\N' ? undefined : new Date(pieces[23]).getTime());
    var destroyed = (pieces[8] == '\\N' ? undefined : new Date(pieces[8]).getTime());
    var last_mod = (pieces[11] == '\\N' ? undefined : new Date(pieces[11]).getTime());
    var zone_state = (pieces[29] == '\\N' ? '' : pieces[29]);
    var brand = 'kvm';
    var uuid = pieces[1];
    var owner_uuid = pieces[3];

    var state;

    if (destroyed !== '') {
        zone_state = 'destroyed';
        state = 'destroyed';
    } else if (zone_state == 'ready' || zone_state == 'running') {
        state = 'running';
    } else {
        state = 'off';
    }

    change = {
        uuid: uuid,
        server_uuid: SERVERS[pieces[5]],
        image_uuid: IMAGES[pieces[4]],
        brand: brand,
        max_physical_memory: Number(pieces[16]),
        max_swap: Number(pieces[13]),
        max_lwps: Number(pieces[21]),
        quota: Number(pieces[22]),
        cpu_shares: Number(pieces[20]),
        zfs_io_priority: Number(pieces[18]),
        ram: Number(pieces[16]),
        internal_metadata: pieces[15],
        customer_metadata: pieces[14],
        cpu_cap: Number(pieces[19]),
        zone_state: zone_state,
        state: state,
        create_timestamp: created_at,
        last_modified: last_mod,
        destroyed: destroyed,
        vcpus: Number(pieces[28]),
        disks: pieces[25],
        zpool: ZPOOLS[pieces[26]] || 'zones'
    };

    // An empty alias is not supported
    if (pieces[2] != '\\N') {
        change.alias = pieces[2];
    }

    var tags = TAGS['VM'][ pieces[0] ];
    if (tags) {
        change.tags = JSON.stringify(tags);
    }

    return change;
}


/**
 * 0 -- id
 * 1 -- name
 * 2 -- customer_id
 * 3 -- reclaimed_at
 * 4 -- setup_at
 * 5 -- setup_by
 * 6 -- cloned_at
 * 7 -- deactivated_at
 * 8 -- destroyed_at
 * 9 -- id_in_ding
 * 10 -- nfs_storage_path
 * 11 -- successful_create_status
 * 12 -- customer_assigned_at
 * 13 -- creation_state
 * 14 -- zfs_storage_pool_id
 * 15 -- disk_used_in_gigabytes
 * 16 -- in_use
 * 17 -- synced_at
 * 18 -- origin_id
 * 19 -- server_id
 * 20 -- ssh_dsa_fingerprint
 * 21 -- ssh_rsa_fingerprint
 * 22 -- authorized_keys
 * 23 -- reserved
 * 24 -- deactivated_by
 * 25 -- destroyed_by
 * 26 -- virtual_ip_id
 * 27 -- cpu_cap
 * 28 -- internal_ips_only
 * 29 -- dataset_id
 * 30 -- ram
 * 31 -- disk
 * 32 -- swap
 * 33 -- lightweight_processes
 * 34 -- cpu_shares
 * 35 -- owner_uuid
 * 36 -- created_at
 * 37 -- updated_at
 * 38 -- alias
 * 39 -- zfs_io_priority
 * 40 -- customer_metadata
 * 41 -- internal_metadata
 * 42 -- blocked_outgoing_ports
 * 43 -- primary_network_id
 * 44 -- latest_heartbeat_cache
 */
function vm_from_zone(pieces) {
    var change;
    var created_at = (pieces[4] == '\\N' ? undefined : new Date(pieces[4]).getTime());
    var destroyed = (pieces[8] == '\\N' ? undefined : new Date(pieces[8]).getTime());
    var last_mod = (pieces[37] == '\\N' ? undefined : new Date(pieces[37]).getTime());
    var zone_state = (pieces[44] == '\\N' ? '' : pieces[44]);
    var brand = 'joyent';
    var uuid = pieces[1];
    var owner_uuid = pieces[35];

    var state;

    if (destroyed !== '') {
        zone_state = 'destroyed';
        state = 'destroyed';
    } else if (zone_state == 'ready' || zone_state == 'running') {
        state = 'running';
    } else {
        state = 'off';
    }

    change = {
        uuid: uuid,
        server_uuid: SERVERS[pieces[19]],
        image_uuid: IMAGES[pieces[29]],
        brand: brand,
        max_physical_memory: Number(pieces[30]),
        max_swap: Number(pieces[32]),
        max_lwps: Number(pieces[33]),
        quota: Number(pieces[31]),
        cpu_shares: Number(pieces[34]),
        zfs_io_priority: Number(pieces[39]),
        ram: Number(pieces[30]),
        internal_metadata: pieces[41],
        customer_metadata: pieces[40],
        cpu_cap: Number(pieces[27]),
        zone_state: zone_state,
        state: state,
        create_timestamp: created_at,
        last_modified: last_mod,
        destroyed: destroyed,
        zpool: ZPOOLS[pieces[14]] || 'zones'
    };

    // An empty alias is not supported
    if (pieces[38] != '\\N') {
        change.alias = pieces[38];
    }

    var tags = TAGS['Zone'][ pieces[0] ];
    if (tags) {
        change.tags = JSON.stringify(tags);
    }

    return change;
}



/**
 * 0 -- id
 * 1 -- hostname
 * 2 -- rack_id
 * 3 -- server_role_id
 * 4 -- ram_in_megabytes
 * 5 -- target_utilization_in_megabytes
 * 6 -- reserved
 * 7 -- setup_at
 * 8 -- cpu_cores
 * 9 -- public_interface
 * 10 -- private_interface
 * 11 -- admin_ssh_access_preferred
 * 12 -- vendor_number
 * 13 -- model
 * 14 -- manufacturer
 * 15 -- operating_system
 * 16 -- uuid
 * 17 -- is_headnode
 * 18 -- latest_boot_at
 * 19 -- target_image_set_at
 * 20 -- created_at
 * 21 -- updated_at
 * 22 -- platform_image_id
 * 23 -- swap_in_gigabytes
 * 24 -- current_status
 * 25 -- hardware_uuid
 * 26 -- boot_args
 * 27 -- vm_capable
 * 28 -- setting_up_at
 */

function transform_servers(file, callback) {
    read_lines(file, function (error, lines) {
        if (error) {
            err_and_exit('Error loading servers file: %s', err.toString());
            return;
        }

        var total = lines.length;
        var changes = [];
        var done = 0;

        try {
            lines.forEach(function (line) {
                if (line === '\\.') {
                    throw 'break';
                }

                var pieces = line.split('\t').map(function(p) {
                    return p !== '\\N' ? p : '';
                });

                if (pieces.length !== 29) {
                    return;
                }

                var uuid = pieces[16];
                var change = {
                    hostname: pieces[1],
                    reserved: pieces[6] === 't' ? 'true' : 'false',
                    uuid: pieces[16],
                    headnode: pieces[17] === 't' ? 'true' : 'false',
                    last_boot: pieces[18],
                    status: pieces[24],
                    hardware_uuid: pieces[25],
                    boot_args: pieces[26] || '{}',
                    datacenter: datacenter,
                    last_updated: pieces[21],
                    objectclass: 'server'
                };

                changes.push(change);
            });
        } catch (e) {
            if (e !== 'break') throw e;
        }

        callback(changes);
    });
}



///--- Mainline

process_argv();

// We do this here because many other transform function might need these
// values
SERVERS = transform_uuids('servers');
IMAGES = transform_uuids('datasets');
ZPOOLS = transform_uuids('zfs_storage_pools');
TAGS = transform_tags('tags');

function printLines(changes) {
    changes.forEach(printChange);

    function printChange(change) {
        console.log(JSON.stringify(change));
        console.log();
    }
}


fs.readdir(directory, function(err, files) {
    if(err) {
        return err_and_exit('Unable to read %s: %s', directory, err.toString());
    }

    files.forEach(function(f) {
        var type = path.basename(f, '.dump');
        if (!/\w+\.dump$/.test(f) || Types.indexOf(type) === -1) {
            return;
        }

        var file = directory + '/' + f;
        switch (type) {
        case 'vms':
        case 'zones':
            transform_vms(file, printLines);
            break;
        case 'servers':
            transform_servers(file, printLines);
            break;
        default:
            console.error('Skipping %s', f);
        }
    });
});
