#!/usr/node/bin/node

var async = require('/usr/node/node_modules/async');
var cp = require('child_process');
var execFile = cp.execFile;
var fs = require('fs');

// Globals
var zone = process.argv[2];
var passed_uuid = process.argv[3];
var config;
var obj = {};

async.series([
    function (cb) {
        // ensure we've got a zone argument
        if (!zone) {
            return cb(new Error('Usage: ' + process.argv[1] + ' <zone> [uuid]'));
        }
        cb();
    }, function (cb) {
        // load the config
        execFile('/bin/bash', ['/lib/sdc/config.sh', '-json'],
            function (error, stdout, stderr)
            {
                if (error) {
                    return cb(new Error('FATAL: failed to get config: ' + stderr));
                }

                try {
                    config = JSON.parse(stdout);
                } catch (e) {
                    return cb(new Error('FATAL: failed to parse config: ' +
                        JSON.stringify(e)));
                }

                cb();
            }
        );
    }, function (cb) {
        // load the zone's JSON template
        fs.readFile('/usbkey/zones/' + zone + '/create.json',
            function (error, data)
            {
                if (error) {
                    return cb(error);
                }

                try {
                    obj = JSON.parse(data);
                } catch (e) {
                    return cb(new Error('exception parsing create.json for ' +
                        zone));
                }
                cb();
            }
        );
    }, function (cb) {
        if (!obj.hasOwnProperty('dataset_uuid')) {
            // find out which dataset we should use for these zones
            fs.readFile('/usbkey/zones/' + zone + '/dataset', function(error, data) {
                if (error) {
                    return cb(new Error('Unable to find dataset name: ' + error.message));
                }
                obj.dataset_name = data.toString().split('\n')[0];
                fs.readFile('/usbkey/datasets/' + obj.dataset_name
                    + '.dsmanifest', function (err, data) {

                    var dsmanifest;

                    if (err) {
                        return cb(new Error('unable to load dsmanifest: ' + err.message));
                    }

                    try {
                        dsmanifest = JSON.parse(data.toString());
                    } catch (e) {
                        return cb(new Error('exception loading dsmanifest for '
                            + zone + ': ' + e.message));
                    }

                    obj.dataset_uuid = dsmanifest.uuid;
                    cb();
                });
            });
        } else {
            // obj already has dataset_uuid so we'll use that.
            cb();
        }
    }, function (cb) {
        // load and apply the package values
        var k, v;
        var pkg, pkgdata;

        if (!config.hasOwnProperty(zone + '_pkg')) {
            return cb(new Error('No package in config for zone: ' + zone));
        }

        for (k in config) {
            v = config[k];

            // fields: # name:ram:swap:disk:cap:nlwp:iopri
            if (k.match('^pkg_')) {
                pkgdata = v.split(':');
                if (pkgdata[0] === config[zone + '_pkg']) {
                    pkg = {};
                    pkg.name = pkgdata[0];
                    pkg.ram = pkgdata[1];
                    pkg.swap = pkgdata[2];
                    pkg.disk = pkgdata[3];
                    pkg.cap = pkgdata[4];
                    pkg.nlwp = pkgdata[5];
                    pkg.iopri = pkgdata[6];
                    //console.log('pkg: ' + JSON.stringify(pkg, null, 2));
                    obj.cpu_shares = Number(pkg.ram); // what MAPI would do.
                    obj.cpu_cap = Number(pkg.cap);
                    obj.zfs_io_priority = Number(pkg.iopri);
                    obj.max_lwps = Number(pkg.nlwp);
                    obj.max_physical_memory = Number(pkg.ram);
                    obj.max_locked_memory = Number(pkg.ram);
                    obj.max_swap = Number(pkg.swap);
                    obj.quota = Number(pkg.disk) / 1024; // we want GiB
                    obj.quota = obj.quota.toFixed(0); // force Integer
                    obj.internal_metadata = {};
                    obj.internal_metadata['package_version'] = '1.0.0';
                    obj.internal_metadata['package_name'] = pkg.name;

                    return cb();
                }
            }
        }

        cb(new Error('Cannot find package "'  + config[zone + '_pkg'] + '" ' +
            'for zone: ' + zone));
    }, function (cb) {
        var newobj;

        // load and apply the parameters for this zone in the config
        if (passed_uuid && passed_uuid.length > 0) {
            obj.uuid = passed_uuid;
        }
        if (config.hasOwnProperty('ufds_admin_uuid')) {
            obj.owner_uuid = config['ufds_admin_uuid'];
        } else {
            console.error('build-payload: no ufds_admin_uuid in config, not '
                + 'setting owner_uuid');
        }
        if (config.hasOwnProperty(zone + '_admin_ip')
            || config.hasOwnProperty(zone + '_admin_ips')) {

            if (!obj.hasOwnProperty('nics')) {
                obj.nics = [];
            }
            newobj = {};
            if (config.hasOwnProperty(zone + '_admin_ip')) {
                newobj.ip = config[zone + '_admin_ip'];
            } else {
                newobj.ip = config[zone + '_admin_ips'];
            }
            if (config.hasOwnProperty('admin_netmask')) {
                newobj.netmask = config['admin_netmask'];
            } else {
                newobj.netmask = '255.255.255.0';
            }
            if (config.hasOwnProperty('admin_gateway')) {
                newobj.gateway = config['admin_gateway'];
            }
            newobj.nic_tag = 'admin';
            newobj.vlan_id = 0;
            newobj.interface = 'net' + obj.nics.length;

            // special case: if Zone has dhcpd sdc_role, set the dhcpd flag.
            if (obj.hasOwnProperty('tags') &&
                obj.tags.hasOwnProperty('smartdc_role') &&
                obj.tags.smartdc_role === 'dhcpd') {

                newobj.dhcp_server = true;
            }
            obj.nics.push(newobj);
        } else {
            console.error('build-payload: no ' + zone + '_admin_ip in config, '
                + 'not adding NIC');
        }

        if (!obj.hasOwnProperty('nics') || obj.nics.length < 1) {
            console.error('build-payload: obj: ' + JSON.stringify(obj));
            cb(new Error('obj has no NICs'));
            return;
        } else {
            // make the last nic 'primary'
            obj.nics.slice(-1)[0].primary = true;
        }

        cb();
    }, function (cb) {
        // load the user-script into metadata
        fs.readFile('/usbkey/zones/' + zone + '/user-script',
            function (error, data)
            {
                if (!obj.hasOwnProperty('customer_metadata')) {
                    obj.customer_metadata = {};
                }
                if (process.env.ASSETS_IP) {
                    obj.customer_metadata['assets-ip'] = process.env.ASSETS_IP;
                }

                if (error) {
                    if (error.code !== 'ENOENT') {
                        return cb(error);
                    } else {
                        return cb();
                    }
                }
                obj.customer_metadata['user-script'] = data.toString();
                cb();
            }
        );
    }, function (cb) {
        // load the user-script into metadata (if we didn't find already)
        if (!obj.customer_metadata.hasOwnProperty('user-script')) {
            fs.readFile('/usbkey/default/user-script.common',
                function (error, data)
                {
                    if (error) {
                        if (error.code !== 'ENOENT') {
                            return cb(error);
                        } else {
                            return cb();
                        }
                    }
                    obj.customer_metadata['user-script'] = data.toString();
                    cb();
                }
            );
        } else {
            cb();
        }
    }, function(cb) {
        obj.customer_metadata['ufds_ldap_root_dn'] = config['ufds_ldap_root_dn'];
        obj.customer_metadata['ufds_ldap_root_pw'] = config['ufds_ldap_root_pw'];
        obj.customer_metadata['ufds_admin_ips'] = config['ufds_admin_ips'];
        cb();
    }
], function (err) {
    if (err) {
        console.error('FATAL: ' + err.message);
        process.exit(1);
    }
    console.log(JSON.stringify(obj, null, 2));
});
