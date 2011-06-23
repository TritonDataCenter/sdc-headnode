{
    "platform-release": "20110623T174013Z"
  , "hvm-platform-release": "HVM"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.122"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "release-20110623"
  , "hvm-agents-shar": "hvm"
  , "datasets": [
      { "name": "smartos-1.3.13"
      , "uuid": "63ce06d8-7ae7-11e0-b0df-1fcf8f45c5d5"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.2"
      , "uuid": "6f6b0a2e-8dcd-11e0-9d84-000c293238eb"
      }
  ]
  , "adminui-checkout": "origin/release-20110623"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-release-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110623"
  , "dhcpd-checkout": "origin/release-20110623"
  , "mapi-checkout": "origin/release-20110623"
  , "portal-checkout": "origin/release-20110623"
  , "cloudapi-checkout": "origin/release-20110623"
  , "pubapi-checkout": "origin/release-20110623"
  , "rabbitmq-checkout": "origin/release-20110623"
  , "upgrades": {
      "agents": [
          "atropos/release-20110623/atropos-release-*"
        , "cloud_analytics/release-20110623/cabase-release-*"
        , "cloud_analytics/release-20110623/cainstsvc-release-20110623-*"
        , "dataset_manager/release-20110623/dataset_manager-20110623-*"
        , "heartbeater/release-20110623/heartbeater-release-20110623-*"
        , "provisioner/release-20110623/provisioner-release-20110623-*"
        , "smartlogin/release-20110623/smartlogin-release-20110623-*"
        , "zonetracker/release-20110623/zonetracker-release-20110623-*"
      ]
  }
}
