# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# Update the config with the correct values.
cat >> /opt/smartdc/hostrouter/config.js <<CONFIG
exports.riakhost = "${hostrouter_riakhost}"
exports.riakbucket = "${hostrouter_riakbucket}"
exports.riakport = "${hostrouter_riakport}"
exports.riakapi = "${hostrouter_riakapi}"
exports.port = 80
CONFIG


# FIXME: Configure riak to use those values up there ^
# Update the files in /opt/riak/etc
# Right now, it's listening on 0.0.0.0, with a set-cookie
# value of "riak".  Super duper insecure and bad!


# Setup and configure riak
if [[ -z $(/usr/bin/svcs -a|grep riak) ]]; then
  echo "Importing riak service"
  /usr/sbin/svccfg import /opt/smartdc/hostrouter/riak-service.xml
  sleep 10 # XXX
  #/usr/sbin/svccfg -s svc:/application/riak:default refresh
  /usr/sbin/svcadm enable -s riak
else
  echo "Restarting riak service"
  /usr/sbin/svcadm disable -s riak
  /usr/sbin/svcadm enable -s riak
fi
