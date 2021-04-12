#!/usr/node/bin/node

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2021 Joyent, Inc.
 */

/*
 * netmask value indexed by prefix length
 * Generated with:
 * var prefix = Array.apply(null, Array(32)).map(function (_, i) {
 *     return (((0x1ffffffff << (32 - i)) - 0xffffffff) >>> 0);
 * });
 */
var netmask = [
    0,           // 0
    2147483648,  // 1
    3221225472,  // 2
    3758096384,  // 3
    4026531840,  // 4
    4160749568,  // 5
    4227858432,  // 6
    4261412864,  // 7
    4278190080,  // 8
    4286578688,  // 9
    4290772992,  // 10
    4292870144,  // 11
    4293918720,  // 12
    4294443008,  // 13
    4294705152,  // 14
    4294836224,  // 15
    4294901760,  // 16
    4294934528,  // 17
    4294950912,  // 18
    4294959104,  // 19
    4294963200,  // 20
    4294965248,  // 21
    4294966272,  // 22
    4294966784,  // 23
    4294967040,  // 24
    4294967168,  // 25
    4294967232,  // 26
    4294967264,  // 27
    4294967280,  // 28
    4294967288,  // 29
    4294967292,  // 30
    4294967294,  // 31
    4294967295   // 32
];

/*
 * prefix length indexed by dotted decimal subnet mask
 */
var prefix = {
    '0.0.0.0': 0,
    '128.0.0.0': 1,
    '192.0.0.0': 2,
    '224.0.0.0': 3,
    '240.0.0.0': 4,
    '248.0.0.0': 5,
    '252.0.0.0': 6,
    '254.0.0.0': 7,
    '255.0.0.0': 8,
    '255.128.0.0': 9,
    '255.192.0.0': 10,
    '255.224.0.0': 11,
    '255.240.0.0': 12,
    '255.248.0.0': 13,
    '255.252.0.0': 14,
    '255.254.0.0': 15,
    '255.255.0.0': 16,
    '255.255.128.0': 17,
    '255.255.192.0': 18,
    '255.255.224.0': 19,
    '255.255.240.0': 20,
    '255.255.248.0': 21,
    '255.255.252.0': 22,
    '255.255.254.0': 23,
    '255.255.255.0': 24,
    '255.255.255.128': 25,
    '255.255.255.192': 26,
    '255.255.255.224': 27,
    '255.255.255.240': 28,
    '255.255.255.248': 29,
    '255.255.255.252': 30,
    '255.255.255.254': 31,
    '255.255.255.255': 32
};

/*
 * The number of IPs in a given prefix length
 * Generated with:
 * var wildcard = Array.apply(null, Array(32)).map(function (_, i) {
 *     return 2**i;
 * });
 */
var wildcard = [
    4294967295, //  0
    2147483647, //  1
    1073741823, //  2
    536870911,  //  3
    268435455,  //  4
    134217727,  //  5
    67108863,   //  6
    33554431,   //  7
    16777215,   //  8
    8388607,    //  9
    4194303,    // 10
    2097151,    // 11
    1048575,    // 12
    524287,     // 13
    262143,     // 14
    131071,     // 15
    65535,      // 16
    32767,      // 17
    16383,      // 18
    8191,       // 19
    4095,       // 20
    2047,       // 21
    1023,       // 22
    511,        // 23
    255,        // 24
    127,        // 25
    63,         // 26
    31,         // 27
    15,         // 28
    7,          // 29
    3,          // 30
    1,          // 31
    0           // 32
];

/*
 * Helper functions
 */

var network_addr = function (ip_as_num, l) {
    return ((ip_as_num & netmask[l]) >>> 0);
};

var ip2num = function (ip) {
    var n = 0;
    ip.split('.').forEach(function (x) {
        if (x < 0 || x > 255) {
            throw 'Octet out of range: ' + x;
        }
        n <<= 8;
        n += parseInt(x, 10);
    });
    return (n >>> 0);
};

var num2ip = function (n) {
    var octet = [
        n >>> 24,
        n >> 16 & 255,
        n >> 8 & 255,
        n & 255
    ];
    return (octet.join('.'));
};

function InetObject(cidr) {
    var self = this,
        cidr_arr;
    self.cidr = cidr;
    cidr_arr = self.cidr.split('/');
    self.ipString = cidr_arr[0];
    self.prefixLength = cidr_arr[1];

    if (self.prefixLength < 0 || self.prefixLength > 32) {
        throw 'Prefix length ' + self.prefixLength + ' out of range.';
    }

    self.ipAsNumber = ip2num(self.ipString);

    self.address = num2ip(self.ipAsNumber);
    self.networkAddrNum = network_addr(self.ipAsNumber, self.prefixLength);
    self.broadcastAddrNum = self.networkAddrNum + wildcard[self.prefixLength];

    self.networkAddr = num2ip(self.networkAddrNum);
    self.broadcastAddr = num2ip(self.broadcastAddrNum);
    self.netmask = num2ip(netmask[self.prefixLength]);
}

/*
 * contains(ip)
 * Does this subnet contain the specified IP?
 * returns bool
 */
InetObject.prototype.contains = function (ip) {
    return this.containsNum(ip2num(ip));
};

/*
 * containsNum(num)
 * Same as contains(), but with number value
 */
InetObject.prototype.containsNum = function (ipNum) {
    if (ipNum > this.networkAddrNum && ipNum < this.broadcastAddrNum) {
        return true;
    }
    return false;
};

/*
 * getMin(n)
 * Get the minimum usable IP, with optional padding
 * n = number of IPs to pad
 */
InetObject.prototype.getMin = function (n) {
    var min;
    n = n || 1;
    min = this.networkAddrNum + n;
    if (this.containsNum(min)) {
        return num2ip(min);
    }
    throw 'IP ' + num2ip(min) + ' not in subnet';
};

/*
 * getMax(n)
 * Get the maximum usable IP, with optional padding
 * n = number of IPs to pad
 */
InetObject.prototype.getMax = function (n) {
    var min;
    n = n || 1;
    min = this.networkAddrNum + wildcard[this.prefixLength] - n;
    if (this.containsNum(min)) {
        return num2ip(min);
    }
    throw 'IP ' + num2ip(min) + ' not in subnet';
};

/*
 * toObj(minPad, maxPad)
 * Serialize the object with usable IPs as an object, optionally pad
 * min and max numbers
 */
InetObject.prototype.toObj = function (minPad, maxPad) {
    return ({
        cidr: this.cidr,
        address: this.address,
        prefix_length: this.prefixLength,
        netmask: this.netmask,
        network: this.networkAddr,
        broadcast: this.broadcastAddr,
        min_ip: this.getMin(minPad),
        max_ip: this.getMax(maxPad)
    });
};

module.exports = {
    InetObject: InetObject
};
