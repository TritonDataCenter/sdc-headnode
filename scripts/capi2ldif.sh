#!/usr/bin/env node
// -*- mode: js -*-

var fs = require('fs');
var path = require('path');



///--- Globals

var Types = ['customers', 'keys', 'blacklists', 'limits', 'metadatum'];
var CustomerIdMap = {};


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


function transform_customers(file, callback) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading customers file: %s', err.toString());

    var changes = [];
    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 26)
        return;
      if (pieces[26] !== '\\N')
        return console.error('%s was a deleted user, skipping.', pieces[6]);

      CustomerIdMap[pieces[4]] = pieces[5];

      var customer = {
        dn: 'uuid=' + pieces[5] + ', ou=users, o=smartdc',
        uuid: pieces[5],
        login: pieces[6],
        email: pieces[13],
        userpassword: pieces[0],
        _salt: pieces[1]
      };

      if (pieces[7] !== '\\N')
        customer.company = pieces[7];
      if (pieces[8] !== '\\N')
        customer.cn = pieces[8];
      if (pieces[9] !== '\\N')
        customer.sn = pieces[9];
      if (pieces[15] !== '\\N')
        customer.address = [pieces[15]];
      if (pieces[16] !== '\\N')
        customer.address.push(pieces[16]);
      if (pieces[17] !== '\\N')
        customer.city = pieces[17];
      if (pieces[18] !== '\\N')
        customer.postalcode = pieces[18];
      if (pieces[19] !== '\\N')
        customer.country = pieces[19];
      if (pieces[22] !== '\\N')
        customer.phone = pieces[22];

      customer.objectclass = 'sdcperson';
      changes.push(customer);
      if (pieces[11] === '2') {
        changes.push({
          dn: 'cn=operators, ou=groups, o=smartdc',
          changetype: 'modify',
          add: 'uniquemember',
          uniquemember: 'uuid=' + pieces[5] + ', ou=users, o=smartdc'
        });
      }
    });

    return callback(changes);
  });
}


function transform_keys(file, callback) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading keys file: %s', err.toString());

    var changes = [];
    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 8)
        return;

      changes.push({
        dn: 'fingerprint=' + pieces[5] +
          ', uuid=' + CustomerIdMap[pieces[1]] +
          ', ou=users, o=smartdc',
        fingerprint: pieces[5],
        name: pieces[2],
        openssh: pieces[3],
        objectclass: 'sdckey'
      });
    });

    return callback(changes);
  });
}


function transform_limits(file, callback) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading limits file: %s', err.toString());

    // Map like:
    // {
    //   :customer_uuid: {
    //     :datacenter: {
    //       :dataset: 3
    //     }
    //   }
    // }
    var limits = {};

    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 7)
        return;

      var customer_uuid = CustomerIdMap[pieces[6]];
      var datacenter = pieces[1];
      if (!limits[customer_uuid])
        limits[customer_uuid] = {};
      if (!limits[customer_uuid][datacenter])
        limits[customer_uuid][datacenter] = {
          dn: 'dclimit=' + datacenter +
            ', uuid=' + customer_uuid +
            ', ou=users, o=smartdc',
          datacenter: datacenter,
          objectclass: 'capilimit'
        };

      limits[customer_uuid][datacenter][pieces[2]] = pieces[3];
    });

    var changes = [];
    Object.keys(limits).forEach(function(uuid) {
      Object.keys(limits[uuid]).forEach(function(dc) {
        changes.push(limits[uuid][dc]);
      });
    });
    return callback(changes);
  });
}


function transform_metadata(file, callback) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading metadata file: %s', err.toString());

    // metadata mapping of:
    // {
    //   :customer_uuid: {
    //     :appkey: {
    //       :key: value
    //     }
    //   }
    // }
    var metadata = {};
    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 4)
        return;

      var customer_uuid = CustomerIdMap[pieces[0]];
      var appkey = pieces[1];
      if (!metadata[customer_uuid])
        metadata[customer_uuid] = {};
      if (!metadata[customer_uuid][appkey])
        metadata[customer_uuid][appkey] = {
          dn: 'metadata=' + appkey +
            ', uuid=' + customer_uuid +
            ', ou=users, o=smartdc',
          cn: appkey,
          objectclass: 'capimetadata'
        };

      metadata[customer_uuid][appkey][pieces[2]] = pieces[3];
    });

    var changes = [];
    Object.keys(metadata).forEach(function(uuid) {
      Object.keys(metadata[uuid]).forEach(function(appkey) {
        changes.push(metadata[uuid][appkey]);
      });
    });
    return callback(changes);
  });
}


function transform_blacklist(file, callback) {
  return read_lines(file, function(err, lines) {
    if (err)
      return err_and_exit('Error loading keys file: %s', err.toString());

    var change = {
      dn: 'cn=blacklist, o=smartdc',
      email: [],
      objectclass: 'emailblacklist'
    };

    lines.forEach(function(line) {
      var pieces = line.split('\t');
      if (pieces.length < 2)
        return;

      change.email.push(pieces[1]);
    });

    return callback(change.email.length ? [change] : []);
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

  // Load customers first, so we can map id -> uuid
  transform_customers(directory + '/customers.dump', function(changes) {
    callback(changes); // Still print these out

    files.forEach(function(f) {
      var type = path.basename(f, '.dump');
      if (!/\w+\.dump$/.test(f) || Types.indexOf(type) === -1)
        return;

      var file = directory + '/' + f;
      switch (type) {
      case 'keys':
        transform_keys(file, callback);
        break;
      case 'customers':
        break;
      case 'limits':
        transform_limits(file, callback);
        break;
      case 'metadatum':
        transform_metadata(file, callback);
        break;
      case 'blacklists':
        transform_blacklist(file, callback);
        break;
      default:
        console.error('Skipping %s', f);
      }
    });
  });
});
