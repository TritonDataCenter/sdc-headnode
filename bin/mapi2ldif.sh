#!/usr/bin/env node
// -*- mode: js -*-

// Copyright (c) 2012, Joyent, Inc., All rights reserved.
// Export data from MAPI PostgreSQL dump to be imported by UFDS into LDAP.

var fs = require('fs');
var path = require('path');
var util = require('util');



///--- Globals

var Types = ['packages'];

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


// Real stuff goes here:

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

      child = exec('/usr/bin/uuid', function (error, stdout, stderr) {
        if (error !== null) {
          console.log('exec error: ' + error);
          return;
        }
        uuid = stdout;
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



///--- Mainline

process_argv();

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
    default:
      console.error('Skipping %s', f);
    }
  });

});
