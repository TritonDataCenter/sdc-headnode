# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# v1
cat > /opt/smartdc/v1/config/production.json <<HERE
{
  "name": "Joyent Public API",
  "url": "http://${PUBLIC_IP}/v1",
  "capi": {
    "url": "${CAPI_URL}",
    "username": "${CAPI_HTTP_ADMIN_USER}",
    "password": "${CAPI_HTTP_ADMIN_PW}"
  },
  "mapi": {
    "${DEFAULT_DATACENTER}": {
      "url": "${MAPI_URL}",
      "username": "${MAPI_HTTP_ADMIN_USER}",
      "password": "${MAPI_HTTP_ADMIN_PW}",
      "resources": {
        "nodejs": {
          "repo": true,
          "domain": "*.no.de",
          "ram": [128, 256, 512, 1024, 2048, 4096]
        },
        "smartos": {
          "ram": [128, 256, 512, 1024, 2048, 4096]
        }
      }
    }
  }
}
HERE

# v2
cat > /opt/smartdc/cloudapi/cfg/config.json <<HERE
{
  "siteName": "${CLOUDAPI_EXTERNAL_URL}",
  "port": 80,
  "datacenter": "${DATACENTER_NAME}",
  "logLevel": 4,
  "capi": {
    "uri": "${CAPI_URL}",
    "username": "${CAPI_HTTP_ADMIN_USER}",
    "password": "${CAPI_HTTP_ADMIN_PW}",
    "authCache": {
      "size": 1000,
      "expiry": 60
    },
    "accountCache": {
      "size": 1000,
      "expiry": 300
    }
  },
  "mapi": {
    "uri": "${MAPI_URL}",
    "username": "${MAPI_HTTP_ADMIN_USER}",
    "password": "${MAPI_HTTP_ADMIN_PW}",
    "datasetCache": {
      "size": 1000,
      "expiry": 300
    }
  },
  "ca": {
    "uri": "${MAPI_URL}",
    "username": "${MAPI_HTTP_ADMIN_USER}",
    "password": "${MAPI_HTTP_ADMIN_PW}"
  },
  "default_limits": {
    "smartos": 1,
    "nodejs": 1,
    "ubuntu": 1
  },
  "default_dataset": "63ce06d8-7ae7-11e0-b0df-1fcf8f45c5d5",
  "default_network": "external",
  "default_package": "regular_128",
  "datacenters": {
    "${DATACENTER_NAME}": "${CLOUDAPI_EXTERNAL_URL}"
  }
}
HERE
