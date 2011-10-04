#!/bin/bash
# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# Update the config with the correct values.
cat >> /opt/smartdc/hostrouter/config.js <<CONFIG
exports.couchdb_host = "${HOSTROUTER_COUCHDB_HOST}"
exports.couchdb_port = ${HOSTROUTER_COUCHDB_PORT}
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
  /usr/sbin/svccfg import /root/couch-service.xml
  sleep 10 # XXX
  /usr/sbin/svcadm enable -s couchdb
else
  echo "Restarting couchdb service"
  /usr/sbin/svcadm disable -s couchdb
  /usr/sbin/svcadm enable -s couchdb
fi

couch=http://localhost:${HOSTROUTER_COUCHDB_PORT}

# create the databases for hostnames and portmapping
curl $couch/hostrouter \
     -X PUT \
     -u admin:a0a6e1a375117c58d77221f10c5ce12e \
     -H content-type:application/json \
     -H content-length:0 \
     -H accept:application/json

# create the design doc for the hostnames couchapp
designdoc=$(node /root/hostnames-design-doc.js)
curl $couch/hostrouter/_design/app \
     -X PUT \
     -d "${designdoc}" \
     -u admin:a0a6e1a375117c58d77221f10c5ce12e \
     -H content-type:application/json \
     -H content-length:${#designdoc} \
     -H accept:application/json
