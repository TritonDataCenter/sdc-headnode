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
 * Network mask indexed by prefix length.
 * Use num2ip() to get the dotted decimal form.
 * E.g.:
 * num2ip(netmask[22]) === "255.255.252.0"
 */
var netmask = [
    0x00000000,  // 0
    0x80000000,  // 1
    0xC0000000,  // 2
    0xE0000000,  // 3
    0xF0000000,  // 4
    0xF8000000,  // 5
    0xFC000000,  // 6
    0xFE000000,  // 7
    0xFF000000,  // 8
    0xFF800000,  // 9
    0xFFC00000,  // 10
    0xFFE00000,  // 11
    0xFFF00000,  // 12
    0xFFF80000,  // 13
    0xFFFC0000,  // 14
    0xFFFE0000,  // 15
    0xFFFF0000,  // 16
    0xFFFF8000,  // 17
    0xFFFFC000,  // 18
    0xFFFFE000,  // 19
    0xFFFFF000,  // 20
    0xFFFFF800,  // 21
    0xFFFFFC00,  // 22
    0xFFFFFE00,  // 23
    0xFFFFFF00,  // 24
    0xFFFFFF80,  // 25
    0xFFFFFFC0,  // 26
    0xFFFFFFE0,  // 27
    0xFFFFFFF0,  // 28
    0xFFFFFFF8,  // 29
    0xFFFFFFFC,  // 30
    0xFFFFFFFE,  // 31
    0xFFFFFFFF   // 32
];

/*
 * prefix length indexed by dotted decimal subnet mask
 * E.g.:
 * prefix["255.255.252.0"] === 22
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
 * Wildcard mask indexed by prefix length.
 * I.e., the number of IPs in a given prefix length.
 * This is the xor of the network mask, and it's often used in the world of
 * network hardware.
 * E.g.:
 *   wildcard[22] === 1024
 * Use num2ip() to get the dotted decimal form.
 * E.g.:
 *   num2ip(wildcard[22]) === "0.0.3.255"
 */
var wildcard = [
    0x00000000,  // 0
    0x00000001,  // 1
    0x00000003,  // 2
    0x00000007,  // 3
    0x0000000F,  // 4
    0x0000001F,  // 5
    0x0000003F,  // 6
    0x0000007F,  // 7
    0x000000FF,  // 8
    0x000001FF,  // 9
    0x000003FF,  // 10
    0x000007FF,  // 11
    0x00000FFF,  // 12
    0x00001FFF,  // 13
    0x00003FFF,  // 14
    0x00007FFF,  // 15
    0x0000FFFF,  // 16
    0x0001FFFF,  // 17
    0x0003FFFF,  // 18
    0x0007FFFF,  // 19
    0x000FFFFF,  // 20
    0x001FFFFF,  // 21
    0x003FFFFF,  // 22
    0x007FFFFF,  // 23
    0x00FFFFFF,  // 24
    0x01FFFFFF,  // 25
    0x03FFFFFF,  // 26
    0x07FFFFFF,  // 27
    0x0FFFFFFF,  // 28
    0x1FFFFFFF,  // 29
    0x3FFFFFFF,  // 30
    0x7FFFFFFF,  // 31
    0xFFFFFFFF   // 32
];

/*
 * Functions
 */

/*
 * Get the network address for an address and given prefix length
 *
 * @param  number   - number format of an IP address.
 * @param  number   - prefix length
 *
 * @return number   - network address as a number
 */
var network_addr = function (ipNum, l) {
    return ((ipNum & netmask[l]) >>> 0);
};

/*
 * Convert IP string in dotted decimal format to a number
 *
 * @param string    - dotted decimal string
 *
 * @return number   - numeric value of IP address
 */
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

/*
 * Convert 32-bit number to dotted decimal representation string
 *
 * @param number    - numeric value of IP address
 *
 * @return string   - String representation of dotted decimal IP address
 */
var num2ip = function (n) {
    var octet = [
        n >>> 24,
        n >> 16 & 255,
        n >> 8 & 255,
        n & 255
    ];
    return (octet.join('.'));
};

/*
 * @constructs  InetObject
 *
 * @arguments   string  - CIDR (ip/prefix length)
 */
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
 * @param   string - dotted decimal representation of IP address
 *
 * @return  bool   - true if IP is within subnet of this InetObject
 */
InetObject.prototype.contains = function (ip) {
    return this.containsNum(ip2num(ip));
};

/*
 * containsNum(num)
 * Same as contains(), but with number value
 *
 * @param   number - numeric value of IP address
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
 *
 * @param   number  - number of IPs to pad
 *
 * @return  string  - dotted decimal representation of IP address
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
 *
 * @param   number  - number of IPs to pad
 *
 * @return  string  - dotted decimal representation of IP address
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
 * Serialize the InetObject with usable IPs as an object, optionally pad
 * min and max numbers. Can be further serialized to JSON.
 *
 * @param   number  - low number to pad
 * @param   number  - high number to pad
 *
 * @return  object  - JS object
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
