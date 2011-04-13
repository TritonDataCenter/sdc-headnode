{
    "platform-release": "develop"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "agents-shar": "develop"
  , "datasets": [
      { "name": "smartos-1.3.12"
      , "uuid": "febaa412-6417-11e0-bc56-535d219f2590"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.2"
      , "uuid": "0586c90c-61a6-11e0-baca-7b2797c68d6d"
      }
  ]
  , "adminui-checkout": "origin/develop"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-master-.*.tar.bz2$"
  , "capi-checkout": "origin/develop"
  , "dhcpd-checkout": "origin/develop"
  , "mapi-checkout": "origin/develop"
  , "portal-checkout": "origin/develop"
  , "pubapi-checkout": "origin/develop"
  , "rabbitmq-checkout": "origin/develop"
  , "upgrades": {
      "agents": [
          "atropos/develop/atropos-develop-*"
        , "cloud_analytics/master/cabase-master-*"
        , "cloud_analytics/master/cainstsvc-master-*"
        , "dataset_manager/develop/dataset_manager-develop-*"
        , "heartbeater/develop/heartbeater-develop-*"
        , "provisioner/develop/provisioner-develop-*"
        , "smartlogin/develop/smartlogin-develop-*"
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
