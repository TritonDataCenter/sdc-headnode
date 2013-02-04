#!/usr/bin/env node
// -*- mode: js -*-

var fs = require('fs');
var path = require('path');



///--- Globals

var Types = ['customers', 'keys', 'blacklists', 'limits', 'metadatum'];
var CustomerIdMap = {};
var blacklist_email = {};
var email_addrs = {};
var cust_uuids = {};
var cust_logins = {};
var key_fingerprints = {};


///--- Helpers

function err_and_exit() {
  console.error.apply(arguments);
  process.exit(1);
}

// The admin UUID is stored in the config file.
// Pass in the admin uuid as an argument.
function usage(msg, code) {
  if (typeof(msg) === 'string')
    console.error(msg);

  console.error('%s <directory>', path.basename(process.argv[1]));
  process.exit(code || 0);
}


function process_argv() {
  if (process.argv.length < 4)
    usage(null, 1);

  try {
    var stats = fs.statSync(process.argv[2]);
    if (!stats.isDirectory())
      usage(process.argv[2] + ' is not a directory', 1);
  } catch (e) {
    usage(process.argv[2] + ' is invalid: ' + e.toString(), 1);
  }

  directory = process.argv[2];
  admin_uuid = process.argv[3];
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

      // skip customers with blacklisted email addresses
      if (pieces[13] in blacklist_email) {
         console.error('%s was a blacklisted user, skipping', pieces[6]);
         return;
      }

      CustomerIdMap[pieces[4]] = pieces[5];

      if (pieces[5] === admin_uuid) {
        uuid = '00000000-0000-0000-0000-000000000000';
      } else {
        uuid = pieces[5];
      }

      // duplicate uuids is a fatal error
      if (uuid in cust_uuids) {
         return err_and_exit('ERROR: %s duplicate uuid', uuid);
      }
      cust_uuids[uuid] = 1;

      // duplicate login is a fatal error
      if (pieces[6] in cust_logins) {
         return err_and_exit('ERROR: %s duplicate login', pieces[6]);
      }
      cust_logins[pieces[6]] = 1;

      // handle duplicate email addresses
      if (pieces[13] in email_addrs) {
         var ecomp = pieces[13].split('@');
         if (ecomp.length != 2)
             return console.error('%s invalid email address, skipping',
                pieces[13]);
         eaddr = ecomp[0] + '+' + pieces[6] + '@' + ecomp[1];
         console.error('%s duplicate email, new addr %s', pieces[13], eaddr);
      } else {
         eaddr = pieces[13];
      }
      email_addrs[eaddr] = 1;

      var customer = {
        dn: 'uuid=' + uuid + ', ou=users, o=smartdc',
        uuid: uuid,
        login: pieces[6],
        email: eaddr,
        userpassword: pieces[0],
        _salt: pieces[1]
      };

      if (pieces[7] !== '\\N')
        customer.company = pieces[7];
      if (pieces[8] !== '\\N')
        customer.cn = pieces[8];
      if (pieces[9] !== '\\N')
        customer.sn = pieces[9];
      if (pieces[15] !== '\\N') {
        customer.address = [pieces[15]];
        if (pieces[16] !== '\\N')
          customer.address.push(pieces[16]);
      } else if (pieces[16] !== '\\N') {
        customer.address = pieces[16];
      }
      if (pieces[17] !== '\\N')
        customer.city = pieces[17];
      if (pieces[18] !== '\\N')
        customer.state = pieces[18];
      if (pieces[19] !== '\\N')
        customer.postalcode = pieces[19];
      if (pieces[20] !== '\\N')
        customer.country = pieces[20];
      if (pieces[23] !== '\\N')
        customer.phone = pieces[23];

      customer.objectclass = 'sdcperson';
      changes.push(customer);
      if (pieces[11] === '2') {
        changes.push({
          dn: 'cn=operators, ou=groups, o=smartdc',
          changetype: 'modify',
          add: 'uniquemember',
          uniquemember: 'uuid=' + uuid + ', ou=users, o=smartdc'
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

      // skip blacklisted customers
      if (!(pieces[1] in CustomerIdMap))
        return;

      cuuid = CustomerIdMap[pieces[1]];

      // skip duplicate key fingerprints
      if (pieces[1] in key_fingerprints) {
         if (key_fingerprints[pieces[1]].indexOf(pieces[5]) != -1) {
            console.error('%s duplicate key fingerprint for customer %s',
               pieces[5], cuuid);
            return;
         }
      } else {
         key_fingerprints[pieces[1]] = [];
      }
      key_fingerprints[pieces[1]].push(pieces[5]);

      // some keys are invalid due to extra spaces, clean those up
      if (/\s{2,}/.test(pieces[3]))
         pieces[3] = pieces[3].replace(/(\s){2,}/, '$1');

      changes.push({
        dn: 'fingerprint=' + pieces[5] +
          ', uuid=' + cuuid +
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

      // skip blacklisted customers
      if (!(pieces[6] in CustomerIdMap))
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

      // skip blacklisted customers
      if (!(pieces[0] in CustomerIdMap))
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
      blacklist_email[pieces[1]] = 1;
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

  // Load blacklist first, so we can find out which customers to skip
  transform_blacklist(directory + '/blacklists.dump', function(changes) {
    callback(changes); // print these out

    // Load customers second, so we can map id -> uuid
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
          break;
        default:
          console.error('Skipping %s', f);
        }
      });
    });
  });
});
