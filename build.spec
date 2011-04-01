{
    "platform-release": "20110331T203330Z"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "agents-shar": "release-20110331-20110331T221932Z"
  , "datasets": [
      { "name": "smartos-1.3.11"
      , "uuid": "e2abe3f6-5668-11e0-bab1-07a4d450d807"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.1"
      , "uuid": "1250c668-5410-11e0-b1de-87052a113a10"
      }
  ]
  , "adminui-checkout": "origin/release-20110331"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-release-20110331-20110331.tar.bz2$"
  , "capi-checkout": "origin/release-20110331"
  , "dhcpd-checkout": "origin/release-20110331"
  , "mapi-checkout": "origin/release-20110331"
  , "portal-checkout": "origin/release-20110331"
  , "pubapi-checkout": "origin/release-20110331"
  , "rabbitmq-checkout": "not-used"
  , "upgrades": {
      "agents": [
          "atropos/release-20110331/atropos-release-20110331-*"
        , "cloud_analytics/release-20110331/cabase-release-20110331-*"
        , "cloud_analytics/release-20110331/cainstsvc-release-20110331-*"
        , "dataset_manager/release-20110331/dataset_manager-release-20110331-*"
        , "heartbeater/release-20110331/heartbeater-release-20110331-*"
        , "provisioner/release-20110331/provisioner-release-20110331-*"
        , "smartlogin/release-20110331/smartlogin-release-20110331-*"
        , "zonetracker/release-20110331/zonetracker-release-20110331-*"
      ]
    , "appzones": [
          "adminui"
        , "capi"
        , "dnsapi"
        , "mapi"
        , "pubapi"
      ]
  }
}
