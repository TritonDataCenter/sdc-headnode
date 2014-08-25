#!/usr/node/bin/node
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/**
 * This generates the `vmadm create` payload for the early zones created at
 * the start of headnode setup, before SAPI is used for this. Currently that
 * just means the 'assets' and 'sapi' zones.
 */

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
    function ensureArgs(cb) {
        if (!zone) {
            return cb(new Error('Usage: ' +
                      process.argv[1] + ' <zone> [uuid]'));
        }
        return cb();
    },
    function loadConfig(cb) {
        execFile('/bin/bash', ['/lib/sdc/config.sh', '-json'],
            function (error, stdout, stderr)
            {
                if (error) {
                    return cb(new Error('FATAL: failed to get config: ' +
                              stderr));
                }

                try {
                    config = JSON.parse(stdout);
                } catch (e) {
                    return cb(new Error('FATAL: failed to parse config: ' +
                        JSON.stringify(e)));
                }

                return cb();
            });
    },
    function loadCreateJson(cb) {
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
                return cb();
            });
    },
    function setOptionalUuid(cb) {
        if (passed_uuid && passed_uuid.length > 0) {
            obj.uuid = passed_uuid;
        }
        return cb();
    },
    function setImageUuid(cb) {
        if (!obj.hasOwnProperty('image_uuid')) {
            // find out which dataset we should use for these zones
            return fs.readFile('/usbkey/zones/' + zone + '/dataset',
                               function readDataset(err, data) {
                if (err) {
                    return cb(new Error('Unable to find dataset name: ' +
                              err.message));
                }
                var image_file_name = data.toString().split('\n')[0];
                return fs.readFile('/usbkey/datasets/' + image_file_name,
                                   function readImgmanifest(_err, _data) {
                    if (_err) {
                        return cb(new Error('unable to load imgmanifest: ' +
                                  _err.message));
                    }

                    try {
                        var imgmanifest = JSON.parse(_data.toString());
                    } catch (e) {
                        return cb(new Error('exception loading imgmanifest for '
                            + zone + ': ' + e.message));
                    }

                    obj.image_uuid = imgmanifest.uuid;
                    return cb();
                });
            });
        } else {
            // obj already has image_uuid so we'll use that.
            return cb();
        }
    },
    function setPackageValues(cb) {
        var k, v;
        var pkg, pkgdata;

        if (!config.hasOwnProperty(zone + '_pkg')) {
            return cb(new Error('No package in config for zone: ' + zone));
        }

        for (k in config) {
            v = config[k];

            // fields: # name:ram:swap:disk:cap:nlwp:iopri:uuid
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
                    pkg.uuid = pkgdata[7];
                    obj.cpu_shares = Number(pkg.ram); // what MAPI would do.
                    obj.cpu_cap = Number(pkg.cap);
                    obj.zfs_io_priority = Number(pkg.iopri);
                    obj.max_lwps = Number(pkg.nlwp);
                    obj.max_physical_memory = Number(pkg.ram);
                    obj.max_locked_memory = Number(pkg.ram);
                    obj.max_swap = Number(pkg.swap);
                    obj.quota = Number(pkg.disk) / 1024; // we want GiB
                    obj.quota = obj.quota.toFixed(0); // force Integer
                    obj.package_version = '1.0.0';
                    obj.package_name = pkg.name;
                    obj.billing_id = pkg.uuid;
                    obj.internal_metadata = {};
                    return cb();
                }
            }
        }

        return cb(new Error('Cannot find package "'  + config[zone + '_pkg'] +
                  '" ' + 'for zone: ' + zone));
    },
    function setConfigValues(cb) {
        if (config.hasOwnProperty('ufds_admin_uuid')) {
            obj.owner_uuid = config['ufds_admin_uuid'];
        } else {
            return cb(new Error('no ufds_admin_uuid in config'));
        }

        // Per OS-2520 we always want to be setting archive_on_delete in SDC
        obj.archive_on_delete = true;

        /* JSSTYLED */
        obj.resolvers = config['binder_admin_ips'].split(/,/g);

        // TODO: is this customer_metadata.resolvers still used?
        if (config.hasOwnProperty('binder_resolver_ips')) {
            if (!obj.hasOwnProperty('customer_metadata')) {
                obj.customer_metadata = {};
            }

            var resolvers = config['binder_resolver_ips'].split(',');

            if (config.hasOwnProperty('dns_resolvers')) {
                resolvers.concat(config['dns_resolvers'].split(','));
            }

            resolvers = resolvers.map(function trim(e) { return e.trim(); })
                .filter(function nonEmpty(e) { return e.length > 0; })
                .join(' ');

            obj.customer_metadata.resolvers = resolvers;
        }

        if (config.hasOwnProperty(zone + '_admin_ip') ||
            config.hasOwnProperty(zone + '_admin_ips')) {

            if (!obj.hasOwnProperty('nics')) {
                obj.nics = [];
            }
            var newobj = {};
            // when there is more than one IP, we take the first one here.
            if (config.hasOwnProperty(zone + '_admin_ip')) {
                newobj.ip = config[zone + '_admin_ip'].split(',')[0];
            } else {
                newobj.ip = config[zone + '_admin_ips'].split(',')[0];
            }
            if (config.hasOwnProperty('admin_netmask')) {
                newobj.netmask = config['admin_netmask'];
            } else {
                newobj.netmask = '255.255.255.0';
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
            return cb(new Error('no "' + zone + '_admin_ip[s]" in config'));
        }

        if (!obj.hasOwnProperty('nics') || obj.nics.length < 1) {
            console.error('build-payload: obj: ' + JSON.stringify(obj));
            return cb(new Error('obj has no NICs'));
        } else {
            // make the last nic 'primary'
            obj.nics.slice(-1)[0].primary = true;
        }

        return cb();
    },
    function setRegistrarConfig(cb) {
        // create the registrar config and insert it into metadata.
        // expect 'registration' to contain a service description
        // for the zone per manta.
        if (obj.hasOwnProperty('registration')) {

            var svcName,
                regConfig,
                zkServers;

            if (!obj.hasOwnProperty('alias'))
                return cb(new Error('No alias provided for ' + zone));

            if (!config.hasOwnProperty('dns_domain'))
                return cb(new Error('No dns_domain in config'));

            if (!config.hasOwnProperty('binder_resolver_ips'))
                return cb(new Error('No binder resolver IPs in config'));

            // by convention, the service name is the alphabetic part of the
            // alias (i.e., 'moray0' -> 'moray') - this is slightly fragile.
            svcName = obj.registration.domain + '.' + config.dns_domain;

            regConfig = {};
            regConfig.registration = obj.registration;
            regConfig.registration.domain = svcName;

            zkServers = config.binder_resolver_ips.split(',')
                .map(function zkConfig(e) {
                    return {
                        host : e,
                        port : 2181
                    };
                });
            regConfig.zookeeper = {};
            regConfig.zookeeper.servers = zkServers;
            regConfig.zookeeper.timeout = 60000;

            if (!obj.hasOwnProperty('customer_metadata'))
                obj.customer_metadata = {};

            obj.customer_metadata['registrar-config'] =
                JSON.stringify(regConfig);
            delete obj.registration; // tidy up
        }
        return cb();
    },
    function setCustomerMetadata(cb) {
        if (!obj.hasOwnProperty('customer_metadata')) {
            obj.customer_metadata = {};
        }
        if (process.env.ASSETS_IP) {
            obj.customer_metadata['assets-ip'] = process.env.ASSETS_IP;
        }
        obj.customer_metadata['sapi-url'] =
            'http://' + config['sapi_admin_ips'];
        obj.customer_metadata['ufds_ldap_root_dn'] =
            config['ufds_ldap_root_dn'];
        obj.customer_metadata['ufds_ldap_root_pw'] =
            config['ufds_ldap_root_pw'];
        obj.customer_metadata['ufds_admin_ips'] = config['ufds_admin_ips'];
        return cb();
    },
    function setUserScript(cb) {
        fs.readFile('/usbkey/default/user-script.common', function (err, data) {
            if (err) {
                return cb(err);
            }
            obj.customer_metadata['user-script'] = data.toString();
            return cb();
        });
    },
    function setMetadataForSapi(cb) {
        // Special cases for SAPI.
        if (zone !== 'sapi') {
            return cb();
        }

        // Explicitly put this first sapi in proto mode.
        obj.customer_metadata['SAPI_PROTO_MODE'] = true;

        // We need the initial usbkey config in the zone so we can pull values
        // for proto-SAPI.
        return fs.readFile('/usbkey/config', function (err, data) {
            if (err) {
                return cb(err);
            }
            obj.customer_metadata['usbkey_config'] = data.toString();
            return cb();
        });
    }
], function (err) {
    if (err) {
        console.error('FATAL: ' + err.message);
        process.exit(1);
    }
    console.log(JSON.stringify(obj, null, 2));
});
