#!/usr/bin/env node
// -*- mode: js -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

var fs = require('fs');
var path = require('path');

///--- Globals

var Types = ['zones', 'vms'];

///--- Helpers

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

function transform_zones(file) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading zones file: %s', err.toString());

    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 45)
        return;
      // if no alias, skip it
      if (pieces[38] === '\\N')
        return;
      // if destroyed, skip it
      if (pieces[8] !== '\\N')
        return;

      tmp = new Buffer(pieces[38]).toString('base64');

      console.log(pieces[1] + ' ' + tmp);

      return;
    });
  });
}

function transform_vms(file) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading vms file: %s', err.toString());

    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 29)
        return;
      // if no alias, skip it
      if (pieces[2] === '\\N')
        return;
      // if destroyed, skip it
      if (pieces[8] !== '\\N')
        return;

      tmp = new Buffer(pieces[2]).toString('base64');

      console.log(pieces[1] + ' ' + tmp);

      return;
    });
  });
}

///--- Mainline

process_argv();

fs.readdir(directory, function(err, files) {
    if(err)
       return err_and_exit('Unable to read %s: %s', directory, err.toString());

    files.forEach(function(f) {
        var type = path.basename(f, '.dump');
        if (!/\w+\.dump$/.test(f) || Types.indexOf(type) === -1)
          return;

        var file = directory + '/' + f;
        switch (type) {
        case 'zones':
          transform_zones(file);
          break;
        case 'vms':
          transform_vms(file);
          break;
        }
    });
});
