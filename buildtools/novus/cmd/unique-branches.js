#!/bin/env node

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 */

 /*
  * This is used by the top level sdc-headnode Makefile to determine
  * part of the path name for build artifacts. If the branches
  * declared by components in the combined build.spec/build.spec.local
  * configuration differ from the branch passed in as the first argument
  * (in our case, the branch of sdc-headnode.git itself), emit a
  * hyphen-separated list of all branches used.
  *
  * This lets us differentiate development headnode builds from each other.
  */
var util = require('util');

var lib_common = require('../lib/common');
var lib_buildspec = require('../lib/buildspec');

function main() {

    if (process.argv.length !== 3) {
        console.error('Usage: unique-branches [branch]');
        process.exit(2);
    }

    var headnode_branch = process.argv[2];

    lib_buildspec.load_build_spec(
            lib_common.root_path('build.spec.merged'),
            function (err, bs) {
        if (err) {
            console.error('ERROR loading build spec: %s', err.stack);
            process.exit(3);
        }

        var branches = {};

        // get each of the build.spec sections that may have branch specifiers
        var zones = bs.get('zones');
        var files = bs.get('files');

        var bits_branch = bs.get('bits-branch', true);
        if (bits_branch !== undefined) {
            branches[bits_branch] = null;
        }

        function find_branches(branch_dic, component_dic, component_name) {
            Object.keys(component_dic).forEach(function find_branches(item) {
                var branch_name = bs.get(
                    util.format('%s|%s|branch', component_name, item), true);
                if (branch_name !== undefined) {
                    branch_dic[branch_name] = null;
                }
            });
        }
        find_branches(branches, zones, 'zones');
        find_branches(branches, files, 'files');

        // if the only branches found were the same as the branch we were
        // given on the command line, then emit nothing and return. This
        // allows build artifacts of the form:
        // [name]-[headnode branch]-[timestamp]-[githash]
        delete branches[headnode_branch];
        var known_branches = Object.keys(branches);
        if (known_branches.length === 1 &&
                known_branches[0] === headnode_branch) {
            process.exit(0);
        }

        // otherwise our artifacts take the form:
        // [name]-[headnode branch]-[branch-list]-[timestamp]-[githash]
        var branch_string = known_branches.sort().join('-');
        if (branch_string.length !== 0) {
            console.log('-' + branch_string);
        }
        process.exit(0);
    });
}

main();
