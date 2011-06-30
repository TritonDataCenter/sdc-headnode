{
    "platform-release": "20110630T203443Z"
  , "hvm-platform-release": "HVM-20110630T191005Z"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.108"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "release-20110630-20110630T195250Z"
  , "hvm-agents-shar": "hvm-20110630T190959Z"
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
  , "adminui-checkout": "origin/release-20110630"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-release-20110630-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110630"
  , "dhcpd-checkout": "origin/release-20110630"
  , "mapi-checkout": "origin/release-20110630"
  , "portal-checkout": "origin/release-20110630"
  , "cloudapi-checkout": "origin/release-20110630"
  , "pubapi-checkout": "origin/release-20110630"
  , "rabbitmq-checkout": "origin/release-20110630"
  , "upgrades": {
      "agents": [
          "atropos/release-20110630/atropos-release-20110630-*"
        , "cloud_analytics/release-20110630/cabase-release-20110630-*"
        , "cloud_analytics/release-20110630/cainstsvc-release-20110630-*"
        , "dataset_manager/release-20110630/dataset_manager-release-20110630-*"
        , "heartbeater/release-20110630/heartbeater-release-20110630-*"
        , "provisioner/release-20110630/provisioner-release-20110630-*"
        , "smartlogin/release-20110630/smartlogin-release-20110630-*"
        , "zonetracker/release-20110630/zonetracker-release-20110630-*"
      ]
  }
}
