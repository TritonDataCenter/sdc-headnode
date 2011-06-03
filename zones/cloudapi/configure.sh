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
  "datasets": {
    "smartos": {
      "1.3.13": "63ce06d8-7ae7-11e0-b0df-1fcf8f45c5d5",
      "_default": "1.3.13"
    },
    "nodejs": {
      "1.1.4": "41da9c2e-7175-11e0-bb9f-536983f41cd8",
      "_default": "1.1.4"
    },
    "ubuntu": {
      "10.04.2.1": "b66fb52a-6a8a-11e0-94cd-b347300c5a06",
      "_default": "10.04.2.1"
    },
    "_default": "smartos"
  },
  "default_network": "external",
  "default_package": "regular_128"
}
HERE
