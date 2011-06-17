# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

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
      "size": 100,
      "expiry": 60
    },
    "accountCache": {
      "size": 100,
      "expiry": 300
    }
  },
  "mapi": {
    "uri": "${MAPI_URL}",
    "username": "${MAPI_HTTP_ADMIN_USER}",
    "password": "${MAPI_HTTP_ADMIN_PW}",
    "datasetCache": {
      "size": 100,
      "expiry": 300
    }
  },
  "ca": {
    "uri": "${MAPI_URL}",
    "username": "${MAPI_HTTP_ADMIN_USER}",
    "password": "${MAPI_HTTP_ADMIN_PW}"
  },
  "rabbitmq": {
    "host": "${RABBIT_IP}",
    "user": "guest",
    "password": "guest",
    "vhost": "/"
  },
  "v1": {
    "host": "${V1_IP}",
    "port": 8080
  },
  "datacenter": "${DATACENTER_NAME}",
  "datacenters": {
    "${DATACENTER_NAME}": "${CLOUDAPI_EXTERNAL_URL}"
  },
  "provisionAuthHook": {
    "plugin": "./plugins/capi_limits",
    "config": {
      "defaults": {
        "smartos": 1,
        "nodejs": 1,
        "ubuntu": 1
      }
    }
  },
  "ipThrottles": {
    "all": {
      "ip": true,
      "burst": 9,
      "rate": 3,
      "overrides": {
        "${PORTAL_ADMIN_IP}": {
          "burst": 0,
          "rate": 0
        }
      }
    },
    "analytics": {
      "ip": true,
      "burst": 100,
      "rate": 10,
      "overrides": {
        "${PORTAL_ADMIN_IP}": {
          "burst": 0,
          "rate": 0
        }
      }
    }
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
    },
    "analytics": {
      "username": true,
      "burst": 1000,
      "rate": 100,
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
