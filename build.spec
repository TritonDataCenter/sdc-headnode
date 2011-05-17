{
    "platform-release": "20110512T181025Z"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "agents-shar": "release-20110512-20110512T204456Z"
  , "datasets": [
      { "name": "smartos-1.3.12"
      , "uuid": "febaa412-6417-11e0-bc56-535d219f2590"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
  ]
  , "adminui-checkout": "origin/release-20110512"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-master-20110512-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110512"
  , "dhcpd-checkout": "origin/release-20110512"
  , "mapi-checkout": "origin/release-20110512"
  , "portal-checkout": "origin/release-20110512"
  , "cloudapi-checkout": "origin/release-20110512"
  , "pubapi-checkout": "origin/release-20110512"
  , "rabbitmq-checkout": "origin/release-20110512"
  , "upgrades": {
      "agents": [
          "atropos/release-20110512/atropos-release-20110512-*"
        , "cloud_analytics/master/cabase-release-20110512-*"
        , "cloud_analytics/master/cainstsvc-release-20110512-*"
        , "dataset_manager/release-20110512/dataset_manager-release-20110512-*"
        , "heartbeater/release-20110512/heartbeater-release-20110512-*"
        , "provisioner/release-20110512/provisioner-release-20110512-*"
        , "smartlogin/release-20110512/smartlogin-release-20110512-*"
        , "zonetracker/release-20110512/zonetracker-release-20110512-*"
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
