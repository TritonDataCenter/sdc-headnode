#!/usr/bin/env node
// -*- mode: js -*-

// Copyright (c) 2012, Joyent, Inc., All rights reserved.
// Export data from MAPI PostgreSQL dump to be imported by UFDS into LDAP.

var fs = require('fs');
var path = require('path');
var util = require('util');



///--- Globals

var Types = ['packages', 'vms', 'zones'];

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



function usage(msg, code) {
  if (typeof(msg) === 'string')
    console.error(msg);

  console.error('%s <directory>', path.basename(process.argv[1]));
  process.exit(code || 0);
}



function process_argv() {
  if (process.argv.length < 3)
    usage(null, 1);

  try {
    var stats = fs.statSync(process.argv[2]);
    if (!stats.isDirectory())
      usage(process.argv[2] + ' is not a directory', 1);
  } catch (e) {
    usage(process.argv[2] + ' is invalid: ' + e.toString(), 1);
  }

  directory = process.argv[2];
}



function read_lines(file, callback) {
  return fs.readFile(file, 'utf8', function(err, data) {
    if (err)
      return callback(err);

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
  var util = require('util'),
      exec = require('child_process').exec,
      child;

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
  var util = require('util'),
      exec = require('child_process').exec,
      child;

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
      obj = [];

    obj.push( pieces[TAG_KEY] + '=' + pieces[TAG_VALUE] );
    hash[ pieces[TAGGABLE_TYPE] ][ pieces[TAGGABLE_ID] ] = obj;
  });

  return hash;
}



function transform_packages(file, callback) {

  var util = require('util'),
      exec = require('child_process').exec,
      child;

  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading packages file: %s', err.toString());

    var changes = [], done = 0, total = lines.length;

    lines.forEach(function(line) {
      var pieces = line.split('\t'), uuid;

      if (pieces.length < 17) {
        done += 1;
        return;
      }

      child = exec('/opt/local/bin/uuid', function (error, stdout, stderr) {
      // child = exec('/usr/bin/uuid', function (error, stdout, stderr) {
        if (error !== null) {
          console.log('exec error: ' + error);
          return;
        }
        uuid = stdout.replace(/^\s+|\s+$/g, '');
        changes.push({
          dn: 'uuid=' + uuid + ', ou=packages, o=smartdc',
          uuid: uuid,
          active: 'true',
          cpu_cap: pieces[5],
          'default': pieces[10] != 'f',
          max_lwps: pieces[6],
          max_physical_memory: pieces[2],
          max_swap: pieces[4],
          name: pieces[1],
          quota: pieces[3],
          urn: pieces[14],
          vcpus: pieces[16],
          version: pieces[13],
          zfs_io_priority: pieces[12],
          objectclass: 'sdcpackage'
        });
        done += 1;
      });
    });
    var checkInt = setInterval(function() {
      if (done >= total) {
        clearInterval(checkInt);
        return callback(changes);
      }
    }, 500);
  });
}


function transform_vms(file, callback) {
  var util = require('util'),
      exec = require('child_process').exec,
      child;

  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading vms file: %s', err.toString());

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


function vm_from_vm(pieces) {
  var change;
  var destroyed = (pieces[8] == '\\N' ? '' : pieces[8]);
  var brand = 'kvm';
  var uuid = pieces[1];
  var owner_uuid = pieces[3];

  var zone_state = pieces[29];
  var state;

  if (destroyed != '') {
    zone_state = 'destroyed';
    state = 'destroyed';
  } else if (zone_state == 'ready' || zone_state == 'running') {
    state = 'running';
  } else {
    state = 'off';
  }

  change = {
    dn: 'vm=' + uuid + ', uuid=' + owner_uuid + ', ou=users, o=smartdc',
    uuid: uuid,
    server_uuid: SERVERS[pieces[5]],
    image_uuid: IMAGES[pieces[4]],
    brand: brand,
    max_physical_memory: pieces[16],
    max_swap: pieces[13],
    max_lwps: pieces[21],
    quota: pieces[22],
    cpu_shares: pieces[20],
    zfs_io_priority: pieces[18],
    alias: pieces[2],
    ram: pieces[16],
    internal_metadata: pieces[15],
    customer_metadata: pieces[14],
    cpu_cap: pieces[19],
    zone_state: zone_state,
    state: state,
    create_timestamp: pieces[23],
    last_modified: pieces[23],
    destroyed: destroyed,
    vcpus: pieces[28],
    disks: pieces[25],
    zpool: ZPOOLS[pieces[26]],
    objectclass: 'vm'
  };

  var tags = TAGS['VM'][ pieces[0] ];
  if (tags)
    change.tags = tags;

  return change;
}


function vm_from_zone(pieces) {
  var change;
  var destroyed = (pieces[8] == '\\N' ? '' : pieces[8]);
  var brand = 'joyent';
  var uuid = pieces[1];
  var owner_uuid = pieces[35];

  var zone_state = pieces[44];
  var state;

  if (destroyed != '') {
    zone_state = 'destroyed';
    state = 'destroyed';
  } else if (zone_state == 'ready' || zone_state == 'running') {
    state = 'running';
  } else {
    state = 'off';
  }

  change = {
    dn: 'vm=' + uuid + ', uuid=' + owner_uuid + ', ou=users, o=smartdc',
    uuid: uuid,
    server_uuid: SERVERS[pieces[19]],
    image_uuid: IMAGES[pieces[29]],
    brand: brand,
    max_physical_memory: pieces[30],
    max_swap: pieces[32],
    max_lwps: pieces[33],
    quota: pieces[31],
    cpu_shares: pieces[34],
    zfs_io_priority: pieces[39],
    alias: pieces[38],
    ram: pieces[30],
    internal_metadata: pieces[41],
    customer_metadata: pieces[40],
    cpu_cap: pieces[27],
    zone_state: zone_state,
    state: state,
    create_timestamp: pieces[4],
    last_modified: pieces[4],
    destroyed: destroyed,
    zpool: ZPOOLS[pieces[14]],
    objectclass: 'vm'
  };

  var tags = TAGS['Zone'][ pieces[0] ];
  if (tags)
    change.tags = tags;

  return change;
}

///--- Mainline

process_argv();

// We do this here because many other transform function might need these
// values
SERVERS = transform_uuids('servers');
IMAGES = transform_uuids('datasets');
ZPOOLS = transform_uuids('zfs_storage_pools');
TAGS = transform_tags('tags');


fs.readdir(directory, function(err, files) {
  if(err)
    return err_and_exit('Unable to read %s: %s', directory, err.toString());

  console.log('version: 1\n');
  function callback(changes) {
    return changes.forEach(function(change) {
      Object.keys(change).forEach(function(k) {
        if (Array.isArray(change[k])) {
          change[k].forEach(function(v) {
            console.log(k + ': ' + v);
          })
        } else {
          console.log(k + ': ' + change[k]);
        }
      });
      console.log();
    });
  }



  files.forEach(function(f) {
    var type = path.basename(f, '.dump');
    if (!/\w+\.dump$/.test(f) || Types.indexOf(type) === -1)
      return;

    var file = directory + '/' + f;
    switch (type) {
    case 'packages':
      transform_packages(file, callback);
      break;
    case 'vms':
    case 'zones':
      transform_vms(file, callback);
    default:
      console.error('Skipping %s', f);
    }
  });

});
