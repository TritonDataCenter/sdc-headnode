#!/usr/bin/env node

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 */

var mod_fs = require('fs');
var mod_dashdash = require('dashdash');
var mod_extsprintf = require('extsprintf');
var mod_path = require('path');

/*
 * This script loads the supplied build.spec file, parses the given
 * configure-branches file and emits a build.spec.branches file with that data.
 *
 * The 'configure-branches' file is assumed to consist of lines of
 * colon-separated component:branch pairs, and that component names are not
 * allowed to contain colons. Comments are allowed, by starting a line with
 * a '#' character.
 *
 * Duplicate keys in configure-branches are not allowed. Some 'files'
 * components should have matching branch values, so we enforce that.
 */

function generate_options() {
    var options = [
        {
            names: ['configure_branches', 'c'],
            type: 'string',
            help: 'input configure-branches file to load',
            helpArg: 'configure-branches'
        },
        {
            names: ['buildspec', 'f' ],
            type: 'string',
            help: 'input build.spec file to load',
            helpArg: 'build.spec'
        },
        {
            names: ['buildspec_branches', 'w'],
            type: 'string',
            help: 'output build.spec.branches file to write',
            helpArg: 'build.spec.branches'
        },
        {
            names: [ 'help', 'h' ],
            type: 'bool',
            help: 'Print this help and exit'
        }
    ];
    return (options);
}

function errprintf() {
    process.stderr.write(mod_extsprintf.sprintf.apply(null, arguments));
}

function printf() {
    process.stdout.write(mod_extsprintf.sprintf.apply(null, arguments));
}

function parse_opts(argv) {
    var parser = mod_dashdash.createParser({
        options: generate_options(),
        allowUnknown: false
    });

    var usage = function (rc) {
        var p = (rc === 0) ? printf : errprintf;

        p('Usage: %s [OPTIONS]\noptions:\n%s\n',
            mod_path.basename(__filename),
            parser.help({
                includeEnv: true
            }));

        if (rc !== undefined) {
            process.exit(rc);
        }
    };

    var opts;
    try {
        opts = parser.parse(argv);
    } catch (ex) {
        errprintf('Error: %s', ex.stack);
        usage(1);
    }

    if (opts.help) {
        usage(0);
    }
    if (opts.configure_branches === undefined ||
        opts.buildspec === undefined ||
        opts.buildspec_branches === undefined) {
            errprintf('error: -c, -f and -w options are required\n');
            usage(0);
    }

    return (opts);
}

function process_line(line, lineno) {

    line = line.trim();
    if (line.length === 0) {
        return;
    }

    if (line[0] === '#') {
        return;
    }

    // we're not using split() because we want exactly two fields
    // but don't want to throw away branch names which may include
    // colons.
    var colon_index = line.indexOf(':');
    if (colon_index === line.length - 1 || colon_index === -1) {
        console.error(
            'Expected key:val pair on line %s, got: %s', lineno,
            line);
        process.exit(1);
    }
    var key = line.slice(0, colon_index).trim();
    var val = line.slice(colon_index + 1, line.length).trim();

    if (key.length === 0 || val.length === 0) {
        console.error(
            'Invalid key/val pair on line %s: %s', lineno, line);
        process.exit(1);
    }
    return ({'key': key, 'val': val});
}

function process_zones_entry(buildspec, key, val, lineno) {
    if (buildspec.zones === undefined) {
        buildspec.zones = {};
    }
    if (buildspec.zones[key] === undefined) {
        buildspec.zones[key] = {'branch': val};
    } else {
        console.log(buildspec.zones[key]);
        console.error(
            'Duplicate key on line %s: %s', lineno, key);
        process.exit(1);
    }
}

function process_files_entry(
        buildspec, key, val, lineno, seen_file_branches) {

    // some files components should have the same branch set
    // if any appear in the configure-branches file. Define
    // those groups, and track the ones we've seen in
    // configure-branches to check for mismatched ones.
    var same_branches = {
        'platform': ['platform', 'platboot', 'platimages'],
        'agents': ['agents', 'agents_md5']
    };

    if (buildspec.files === undefined) {
        buildspec.files = {};
    }
    if (seen_file_branches.indexOf(key) !== -1) {
        console.error(
            'Error: duplicate key on line %s: %s', lineno, key);
        process.exit(1);
    } else {
        seen_file_branches.push(key);
        buildspec.files[key] = {'branch': val};
    }
    // set any required duplicates, also looking for mismatched
    // values from configure-branches
    for (var same_key in same_branches) {
        // the list of keys that must have the same
        var same_list = same_branches[same_key];

        if (same_list.indexOf(key) !== -1) {
            for (var j = 0; j < same_list.length; j++) {
                var comp = same_list[j];
                if (comp === key) {
                    continue;
                }
                var existing_val = buildspec.files[comp];
                if (existing_val !== undefined &&
                    existing_val.branch !== val) {
                    console.error(
                        'Error: values across %s must be identical. ' +
                        'See line %s: %s',
                        same_list.join(', '), lineno, key);
                    process.exit(1);
                } else {
                    buildspec.files[comp] = {'branch': val};
                }
            }
        }
    }
}

var opts = parse_opts();

try {
    var bs_file = mod_fs.readFileSync(opts.buildspec, 'utf-8');

    var bs_data = JSON.parse(bs_file);
    var known_zones = Object.keys(bs_data.zones);
    var known_files = Object.keys(bs_data.files);
    var out_buildspec = {};

    var data = mod_fs.readFileSync(opts.configure_branches, 'utf-8');

    var vals = data.split('\n');
    var seen_file_branches = [];

    for (var i = 0 ; i < vals.length; i++) {
        var lineno = i + 1;
        var kv = process_line(vals[i], lineno);
        if (kv === undefined) {
            continue;
        }

        // Determine whether we have 'zones', 'files' or other keys.
        if (known_zones.lastIndexOf(kv.key) > -1) {
            process_zones_entry(out_buildspec, kv.key, kv.val, lineno);
        } else if (known_files.lastIndexOf(kv.key) > -1) {
            process_files_entry(
                out_buildspec, kv.key, kv.val, lineno, seen_file_branches);
        } else {
            if (bs_data[kv.key] === undefined) {
                console.error(
                    'Unknown build.spec key in configure-branches ' +
                    'file, line %s: %s', lineno, kv.key);
                process.exit(1);
            }
            out_buildspec[kv.key] = kv.val;
        }
    }
    mod_fs.writeFileSync(opts.buildspec_branches,
        JSON.stringify(out_buildspec, null, 4),
        'utf-8');
} catch (err) {
    console.error('Error converting configure-branches: %s', err);
    process.exit(1);
}
