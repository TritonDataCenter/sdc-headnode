{
    "platform-release": "20110325T200214Z"
  , "build-tgz": "true"
  , "agents-shar": "release-20110324-20110325T215215Z"
  , "datasets": [
      { "name": "smartos-1.3.11"
      , "uuid": "e2abe3f6-5668-11e0-bab1-07a4d450d807"
      }
    , { "name": "nodejs-1.1.1"
      , "uuid": "1250c668-5410-11e0-b1de-87052a113a10"
      }
  ]
  , "adminui-checkout": "origin/release-20110324"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-master-20110324.tar.bz2$"
  , "capi-checkout": "origin/release-20110324"
  , "dhcpd-checkout": "origin/release-20110324"
  , "mapi-checkout": "origin/release-20110324"
  , "portal-checkout": "origin/release-20110324"
  , "pubapi-checkout": "origin/release-20110324"
  , "rabbitmq-checkout": "not-used"
  , "upgrades": {
      "agents": [
          "atropos/develop/atropos-develop-*"
        , "cloud_analytics/master/cabase-master-*"
        , "cloud_analytics/master/cainstsvc-master-*"
        , "dataset_manager/develop/dataset_manager-develop-*"
        , "heartbeater/develop/heartbeater-develop-*"
        , "provisioner/develop/provisioner-develop-*"
        , "zonetracker/develop/zonetracker-develop-*"
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
