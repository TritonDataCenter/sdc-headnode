{
    "platform-release": "20110428T203701Z"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "agents-shar": "release-20110428-20110428T225715Z"
  , "datasets": [
      { "name": "smartos-1.3.12"
      , "uuid": "febaa412-6417-11e0-bc56-535d219f2590"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.3"
      , "uuid": "7456f2b0-67ac-11e0-b5ec-832e6cf079d5"
      }
  ]
  , "adminui-checkout": "origin/release-20110428"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-release-20110428-20110428.tar.bz2$"
  , "capi-checkout": "origin/release-20110428"
  , "dhcpd-checkout": "origin/release-20110428"
  , "mapi-checkout": "origin/release-20110428"
  , "portal-checkout": "origin/release-20110428"
  , "pubapi-checkout": "origin/release-20110428"
  , "rabbitmq-checkout": "origin/release-20110428"
  , "upgrades": {
      "agents": [
          "atropos/release-20110428/atropos-release-20110428-*"
        , "cloud_analytics/master/cabase-release-20110428-*"
        , "cloud_analytics/master/cainstsvc-release-20110428-*"
        , "dataset_manager/release-20110428/dataset_manager-release-20110428-*"
        , "heartbeater/release-20110428/heartbeater-release-20110428-*"
        , "provisioner/release-20110428/provisioner-release-20110428-*"
        , "smartlogin/release-20110428/smartlogin-release-20110428-*"
        , "zonetracker/release-20110428/zonetracker-release-20110428-*"
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
