#!/bin/bash
# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# Update the config with the correct values.
cat >> /opt/smartdc/hostrouter/config.js <<CONFIG
exports.couchdbhost = "${HOSTROUTER_COUCHDB_HOST}"
exports.couchdbport = ${HOSTROUTER_COUCHDB_PORT}
exports.port = 80
CONFIG

# The headnode hostrouter db listens on 0.0.0.0, so that it is visible
# on the hostrouteradmin network (for compute-node hostrouters) and the
# admin network (for cloudapi).

# backup first!
cp /opt/local/etc/couchdb/local.ini /root/couchdb-local.ini

cat > /opt/local/etc/couchdb/local.ini <<CONFIG
[httpd]
bind_address = 0.0.0.0
port = ${HOSTROUTER_COUCHDB_PORT}

[admins]
admin = a0a6e1a375117c58d77221f10c5ce12e
CONFIG

# Setup and configure couchdb
if [[ -z $(/usr/bin/svcs -a|grep couchdb) ]]; then
  echo "Importing couchdb service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/couchdb.xml
  sleep 10 # XXX
  /usr/sbin/svcadm enable -s couchdb
else
  echo "Restarting couchdb service"
  /usr/sbin/svcadm disable -s couchdb
  /usr/sbin/svcadm enable -s couchdb
fi

# create the databases for hostnames and portmapping
curl -X PUT \
     -u admin:a0a6e1a375117c58d77221f10c5ce12e \
     -H content-type:application/json \
     -H accept:application/json \
     http://${HOSTROUTER_COUCHDB_HOST}:${HOSTROUER_COUCHDB_PORT}/hostrouter
