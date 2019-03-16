#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

#
# Create a "light" version of sdc-clients and its npm deps. Specifically this
# is about having a binary-module-free and small distro of sdc-clients for
# usage in the platform.
#
# Here "light" means:
# - no ldapjs and the clients that use it (not currently needed by platform
#   scripts)
# - no binary modules
# - Stripped down npm module installs. We attempt to get it down to:
#       $NAME/
#           package.json
#           index.js
# - flatten deps (i.e. no deeply nested node_modules dirs)
#
#
# Warnings:
# - This *does* involve taking liberties with specified dependency
#   versions. E.g. You get the version of the shared dtrace-provider already
#   in "/usr/node/node_modules/dtrace-provider".
# - This will start with the node-sdc-clients.git#master and attempt to get
#   the version of deps that its package.json specifies. However, you need
#   to worry about recursive version mismatches and new/removed module
#   deps manually.
#
#
# Usage:
#       ./mk-sdc-clients-light.sh [SHA] [TARGET-DIR] [LIBS...]
#
# By default SHA is "master". It is the version of node-sdc-clients.git to use.
# By default TARGET-DIR is "./node_modules/sdc-clients".
# By default if LIBS is excluded, then all sdc-clients/lib/*.js API modules
#       are included. Note that UFDS-direct "APIs" are always excluded
#       (ufds.js, etc.) If any LIBS are specified, then only those are
#       kept.
#
#
# Examples:
#   ./mk-sdc-clients-light.sh master node_modules/sdc-clients imgapi.js amon.js
#

if [ "$TRACE" != "" ]; then
    # BASHSTYLED
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail



#---- support stuff

function fatal
{
    echo "$(basename $0): fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0
    fatal "error exit status $1 at line $2"
}

trap 'errexit $? $LINENO' EXIT



#---- mainline

SHA=$1
if [[ -z "$SHA" ]]; then
    SHA=master
fi
shift

D=$1
if [[ -z "$D" ]]; then
    D=node_modules/sdc-clients
fi
shift

LIBS=$*

rm -rf $D
mkdir -p $D
cd $D

# sdc-clients (stripped of ldap-using clients)
mkdir _repos
(cd _repos && git clone git@github.com:joyent/node-sdc-clients.git)
(cd _repos/node-sdc-clients && git checkout $SHA)
mv _repos/node-sdc-clients/{package.json,lib} .
(cd lib && rm -f config.js package.js ufds.js assertions.js)

if [[ -n "$LIBS" ]]; then
    for LIB in $(cd lib && ls -1 *api.js) amon.js; do
        if [[ -z $(echo "$LIBS" | grep "\<$LIB\>") ]]; then
            rm -f lib/$LIB
        fi
    done
fi

# assert-plus
VER=$(json -f package.json dependencies.assert-plus)
npm install assert-plus@$VER

# async
VER=$(json -f package.json dependencies.async)
npm install async@$VER
(cd node_modules/async \
    && rm -rf .[a-z]* README.md Makefile*)

# backoff
VER=$(json -f package.json dependencies.backoff)
npm install backoff@$VER
(cd node_modules/backoff \
    && rm -rf .[a-z]* examples README.md tests)

# clone
VER=$(json -f package.json dependencies.clone)
npm install clone@$VER
(cd node_modules/clone \
    && rm -rf .[a-z]* README.md test.js)

# jsprim
VER=$(json -f package.json dependencies.jsprim)
npm install jsprim@$VER
(cd node_modules/jsprim \
    && rm -rf .[a-z]* node_modules README.md Makefile* test jsl.node.conf)

# extsprintf (used by jsprim)
VER=$(json -f node_modules/jsprim/package.json dependencies.extsprintf)
npm install extsprintf@$VER
(cd node_modules/extsprintf \
    && rm -rf .[a-z]* README.md examples Makefile* jsl.node.conf)

# json-schema (used by jsprim)
VER=$(json -f node_modules/jsprim/package.json dependencies.json-schema)
npm install json-schema@$VER
(cd node_modules/json-schema \
    && rm -rf .[a-z]* README.md examples Makefile* test)

# lomstream
VER=$(json -f package.json dependencies.lomstream)
npm install lomstream@$VER
(cd node_modules/lomstream \
    && rm -rf .[a-z]* node_modules README.md test)

# vstream (used by lomstream)
VER=$(json -f node_modules/lomstream/package.json dependencies.vstream)
npm install vstream@$VER
(cd node_modules/vstream \
     && rm -rf .[a-z]* node_modules README.md examples Makefile* \
           jsl.node.conf tests)

# lru-cache
VER=$(json -f package.json dependencies.lru-cache)
npm install lru-cache@$VER
(cd node_modules/lru-cache \
    && rm -rf .[a-z]* AUTHORS README.md test)

# once
VER=$(json -f package.json dependencies.once)
npm install once@$VER
(cd node_modules/once \
    && rm -rf .[a-z]* README.md test)


# restify-clients
VER=$(json -f package.json dependencies.restify-clients)
npm install restify-clients@$DEP
(cd node_modules/restify-clients \
     && rm -rf node_modules/{bunyan,dtrace-provider,lodash} \
           node_modules/restify-errors/node_modules \
           bin README.md CHANGES.md .npmignore)

# restify-errors
VER=$(json -f package.json dependencies.restify-errors)
npm install restify-errors@$VER
(cd node_modules/restify-errors \
    && rm -rf .[a-z]* node_modules README.md test)

# lodash (used by restify)
VER=$(json -f node_modules/restify-clients/package.json dependencies.lodash)
npm install lodash@$VER
(cd node_modules/lodash \
    && rm -rf .[a-z]* README.md test)


# smartdc-auth
VER=$(json -f package.json dependencies.smartdc-auth)
npm install smartdc-auth@$VER
(cd node_modules/smartdc-auth \
     && rm -rf .[a-z]* \
           node_modules/{bunyan,clone,dashdash,once} \
           node_modules/{sshpk,sshpk-agent,vasync,verror} \
           README.md bin)

# dashdash (used by smartdc-auth)
VER=$(json -f node_modules/smartdc-auth/package.json dependencies.dashdash)
npm install dashdash@$VER
(cd node_modules/dashdash \
    && rm -rf .[a-z]* node_modules README.md examples Makefile*)

# sshpk-agent (used by smartdc-auth)
VER=$(json -f node_modules/smartdc-auth/package.json dependencies.sshpk-agent)
npm install sshpk-agent@$VER
(cd node_modules/sshpk-agent \
     && rm -rf .[a-z]* node_modules/{sshpk,verror} \
           node_modules/mooremachine/node_modules \
           README.md examples Makefile*)

# sshpk
VER=$(json -f package.json dependencies.sshpk)
npm install sshpk@$VER
(cd node_modules/sshpk \
    && rm -rf .[a-z]* node_modules/dashdash README.md bin)

# vasync
VER=$(json -f package.json dependencies.vasync)
npm install vasync@$VER
(cd node_modules/vasync \
     && rm -rf .[a-z]* node_modules README.md examples Makefile* \
           jsl.node.conf tests)

# verror
VER=$(json -f package.json dependencies.verror)
npm install verror@$VER
(cd node_modules/verror \
    && rm -rf .[a-z]* node_modules README.md examples \
    Makefile* jsl.node.conf tests)

# core-util-is (used by verror)
VER=$(json -f package.json dependencies.core-util-is)
npm install core-util-is@$VER
(cd node_modules/core-util-is \
    && rm -rf .[a-z]* README.md test)


# bunyan
# Patch bunyan usages to use the platform one, because it has dtrace-provider
# hooked up.
# BEGIN BASHSTYLED
patch -p0 <<PATCH
--- node_modules/restify-clients/lib/helpers/bunyan.js.orig	2018-07-27 13:51:32.831768801 -0400
+++ node_modules/restify-clients/lib/helpers/bunyan.js	2018-07-27 13:52:22.056602085 -0400
@@ -6,7 +6,12 @@
 var util = require('util');
 
 var assert = require('assert-plus');
-var bunyan = require('bunyan');
+var bunyan;
+if (process.platform === 'sunos') {
+    bunyan = require('/usr/node/node_modules/bunyan');
+} else {
+    bunyan = require('bunyan');
+}
 var lru = require('lru-cache');
 var uuid = require('uuid');

--- node_modules/restify-clients/lib/helpers/dtrace.js.orig	2018-07-27 13:54:18.319208324 -0400
+++ node_modules/restify-clients/lib/helpers/dtrace.js	2018-07-27 13:54:42.770125513 -0400
@@ -27,7 +27,7 @@
 module.exports = (function exportStaticProvider() {
     if (!PROVIDER) {
         try {
-            var dtrace = require('dtrace-provider');
+            var dtrace = require('/usr/node/node_modules/dtrace-provider');
             PROVIDER = dtrace.createDTraceProvider('restify');
         } catch (e) {
             PROVIDER = {

--- node_modules/sshpk-agent/node_modules/mooremachine/lib/fsm.js.orig	2018-07-27 13:55:30.474963945 -0400
+++ node_modules/sshpk-agent/node_modules/mooremachine/lib/fsm.js	2018-07-27 13:55:52.307893039 -0400
@@ -18,7 +18,7 @@
 var mod_dtrace;
 
 try {
-	mod_dtrace = require('dtrace-provider');
+	mod_dtrace = require('/usr/node/node_modules/dtrace-provider');
 } catch (e) {
 	mod_dtrace = undefined;
 }
PATCH
# END BASHSTYLED

rm -rf node_modules/.bin
rm -rf _repos
