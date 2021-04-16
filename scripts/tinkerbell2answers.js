#!/usr/node/bin/node

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2021 Joyent, Inc.
 */

var crypto = require('crypto');
var fs = require('fs');
var ipnet = require('./ipnet');

var answers = {
    config_console: 'serial',
    skip_instructions: true,
    simple_headers: false,
    skip_final_confirm: true,
    skip_edit_config: true,
    skip_dns_check: true,
    datacenter_company_name: null,
    region_name: null,
    datacenter_name: null,
    datacenter_location: null,
    admin_nic: null,
    admin_ip: null,
    admin_provisionable_start: '<default>',
    admin_netmask: null,
    admin_gateway: '<default>',
    setup_external_network: true,
    external_nic: null,
    external_ip: null,
    external_vlan_id: 0,
    external_provisionable_start: '<default>',
    external_provisionable_end: '<default>',
    external_netmask: null,
    external_gateway: null,
    headnode_default_gateway: '<default>',
    dns_resolver1: null,
    dns_resolver2: null,
    dns_domain: null,
    dns_search: null,
    dhcp_range_end: '<default>',
    ntp_host: null,
    root_password: null,
    admin_password: null,
    mail_to: null,
    mail_from: null,
    phonehome_automatic: false,
    update_channel: null
};

// We're just going to assume an arg was passed, and that it exists.
// If this assumption is wrong, an exception will be thrown which is OK
// since there's nothing else worthwhile doing.
// In particular, prompt-config.sh will only call us if a valid tinkerbell
// metadata file was found.
var tinkerbell = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));

// Values always present in tinkerbell
answers.datacenter_name = tinkerbell.facility;
answers.admin_nic = tinkerbell.network.interfaces[1].mac;
answers.external_nic = tinkerbell.network.interfaces[0].mac;

// Derived Values
var macsplit = answers.admin_nic.split(':').map(function (x) {
    return Number('0x' + x);
});
var admin_net_s = '10.' + macsplit[4] + '.' + macsplit[5] + '.10/22';
var admin_net = new ipnet.InetObject(admin_net_s);
var external_net = tinkerbell.network.addresses.filter(function (x) {
    return (x.public);
});

console.error(external_net);

answers.admin_ip = admin_net.getMin(10);
answers.admin_netmask = admin_net.netmask;

answers.external_ip = external_net[0].address;
answers.external_netmask = external_net[0].netmask;
answers.external_gateway = external_net[0].gateway;

// Overridable values
answers.datacenter_company_name = tinkerbell.customdata.company_name || 'none';
answers.region_name = tinkerbell.customdata.region_name ||
    answers.datacenter_name.match(/^[a-z]+/)[0];
answers.datacenter_location = tinkerbell.customdata.datacenter_location ||
    'none';
answers.dns_resolver1 = tinkerbell.customdata.dns_resolver1 || '8.8.8.8';
answers.dns_resolver2 = tinkerbell.customdata.dns_resolver2 || '8.8.4.4';
answers.dns_domain = tinkerbell.customdata.dns_domain || 'triton.local';
answers.dns_search = answers.dns_domain;
answers.ntp_host = tinkerbell.customdata.ntp_host || '0.smartos.pool.ntp.org';
answers.mail_to = tinkerbell.customdata.mail_to || 'root@localhost';
answers.mail_from = tinkerbell.customdata.mail_from ||
    'support@' + answers.dns_domain;
answers.update_channel = tinkerbell.customdata.update_channel || 'release';

answers.root_password = tinkerbell.customdata.root_password ||
    crypto.randomBytes(16).toString('hex');
answers.admin_password = tinkerbell.customdata.admin_password ||
    crypto.randomBytes(16).toString('hex');

// The End
console.log(JSON.stringify(answers));
