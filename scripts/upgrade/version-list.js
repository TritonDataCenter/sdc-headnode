#!/usr/node/bin/node

/*
 * Copyright (c) 2013, Joyent, Inc. All rights reserved.
 *
 * version-list.js - creates a list of currently-deployed images
 * and zones.
 */

var assert = require('/opt/smartdc/node_modules/assert-plus');
var async = require('/usr/node/node_modules/async');
var cp = require('child_process');
var exec = cp.exec;
var sdc = require('/opt/smartdc/node_modules/sdc-clients');
var Logger = require('/usr/node/node_modules/bunyan');
var sprintf = require('util').format;

var vms_cmd = "vmadm lookup -j -o uuid,image_uuid,tags tags.smartdc_role=~[a-z]";
var zone_list = [
    "adminui", "amon", "ca", "cnapi", "dapi", "dhcpd", "fwapi",
    "imgapi", "napi", "sapi", "usageapi", "vmapi", "workflow"
]

