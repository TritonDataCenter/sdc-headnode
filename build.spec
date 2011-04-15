{
    "platform-release": "20110414T185150Z"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "agents-shar": "release-20110414-20110414T231141Z"
  , "datasets": [
      { "name": "smartos-1.3.12"
      , "uuid": "febaa412-6417-11e0-bc56-535d219f2590"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.2"
      , "uuid": "0586c90c-61a6-11e0-baca-7b2797c68d6d"
      }
  ]
  , "adminui-checkout": "origin/release-20110414"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-release-20110414-20110414.tar.bz2$"
  , "capi-checkout": "origin/release-20110414"
  , "dhcpd-checkout": "origin/release-20110414"
  , "mapi-checkout": "origin/release-20110414"
  , "portal-checkout": "origin/release-20110414"
  , "pubapi-checkout": "origin/release-20110414"
  , "rabbitmq-checkout": "origin/release-20110414"
  , "upgrades": {
      "agents": [
          "atropos/release-20110414/atropos-release-20110414-*"
        , "cloud_analytics/release-20110414/cabase-release-20110414-*"
        , "cloud_analytics/release-20110414/cainstsvc-release-20110414-*"
        , "dataset_manager/release-20110414/dataset_manager-release-20110414-*"
        , "heartbeater/release-20110414/heartbeater-release-20110414-*"
        , "provisioner/release-20110414/provisioner-release-20110414-*"
        , "smartlogin/release-20110414/smartlogin-release-20110414-*"
        , "zonetracker/release-20110414/zonetracker-release-20110414-*"
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
