/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2016 Joyent, Inc.
 */


var mod_extsprintf = require('extsprintf');

var DPRINTF_EPOCH = process.hrtime();

function
dprintf()
{
    if (!process.env.DEBUG) {
        return;
    }

    var msg = mod_extsprintf.sprintf.apply(null, arguments);
    var now = process.hrtime(DPRINTF_EPOCH);
    var msec = now[0] * 1000 + now[1] / 1000000;

    var fmt = '[%6d] %s';
    if (msg[msg.length - 1] !== '\n') {
        fmt += '\n';
    }

    process.stderr.write(mod_extsprintf.sprintf(fmt, msec, msg));
}

module.exports = {
    dprintf: dprintf
};

/* vim: set ts=4 sts=4 sw=4 et: */
