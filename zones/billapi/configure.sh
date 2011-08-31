# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

cat > /opt/smartdc/billapi/config/config.json <<HERE
{
  "siteName": "${BILLAPI_EXTERNAL_URL}",
  "port": 443,
  "cert": "./ssl/cert.pem",
  "key": "./ssl/key.pem",
  "logLevel": 4,
  "user": "${HTTP_ADMIN_USER}",
  "password": "${HTTP_ADMIN_PW}",
  "amqp": {
    "host": "${RABBIT_IP}",
    "login": "guest",
    "password": "guest",
    "vhost": "/",
    "port": 5672
  },
  "riak": {
    "host": "${RIAK_IP}",
    "port": "${RIAK_PORT}"
  },
  "userThrottles": {
    "all": {
      "username": true,
      "burst": 30,
      "rate": 10,
      "overrides": {
        "${CAPI_ADMIN_LOGIN}": {
          "burst": 0,
          "rate": 0
        }
      }
    }
  }
}
HERE
