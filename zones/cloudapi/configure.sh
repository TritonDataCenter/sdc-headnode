# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

cat > /opt/smartdc/cloudapi/cfg/config.json <<HERE
{
  "siteName": "${CLOUDAPI_EXTERNAL_URL}",
  "port": 443,
  "cert": "./ssl/cert.pem",
  "key": "./ssl/key.pem",
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
    "uri": "${CA_URL}"
  },
  "rabbitmq": {
    "host": "${RABBIT_IP}",
    "user": "guest",
    "password": "guest",
    "vhost": "/"
  },
  "portal": {
    "host": "${PORTAL_IP}"
  },
  "datacenters": {
    "${DATACENTER_NAME}": "${CLOUDAPI_EXTERNAL_URL}"
  },
  "preProvisionHook": {
    "plugin": "./plugins/capi_limits",
    "enabled": true,
    "config": {
      "datacenter": "${DATACENTER_NAME}",
      "defaults": {
        "smartos": 1,
        "nodejs": 1,
        "ubuntu": 1
      }
    }
  },
  "postProvisionHook": {
    "plugin": "./plugins/machine_email",
    "enabled": false,
    "config": {
      "sendmail": "/opt/local/sbin/sendmail -i",
      "from": "support@joyent.com",
      "subject": "Your SmartDataCenter machine is provisioning",
      "body": "Check /my/machines for updates"
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
