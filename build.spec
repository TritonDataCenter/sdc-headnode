{
    "platform-release": "20110714T190221Z"
  , "hvm-platform-release": "HVM-20110714T185818Z"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.138"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "release-20110714-20110714T182947Z"
  , "hvm-agents-shar": "hvm-20110714T185745Z"
  , "datasets": [
      { "name": "smartos-1.3.15"
      , "uuid": "184c9b38-ad3d-11e0-bad6-1b7240aaa5fc"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.3"
      , "uuid": "3ee607e0-acfa-11e0-891d-f7db5c24f5ba"
      }
  ]
  , "adminui-checkout": "origin/release-20110714"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-release-20110714-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110714"
  , "dhcpd-checkout": "origin/release-20110714"
  , "mapi-checkout": "origin/release-20110714"
  , "portal-checkout": "origin/release-20110714"
  , "cloudapi-checkout": "origin/release-20110714"
  , "pubapi-checkout": "origin/release-20110714"
  , "rabbitmq-checkout": "origin/release-20110714"
  , "upgrades": {
      "agents": [
          "atropos/release-20110714/atropos-release-20110714-*"
        , "cloud_analytics/release-20110714/cabase-release-20110714-*"
        , "cloud_analytics/release-20110714/cainstsvc-release-20110714-*"
        , "dataset_manager/release-20110714/dataset_manager-release-20110714-*"
        , "heartbeater/release-20110714/heartbeater-release-20110714-*"
        , "provisioner-v2/release-20110714/provisioner-v2-release-20110714-*"
        , "smartlogin/release-20110714/smartlogin-release-20110714-*"
        , "zonetracker/release-20110714/zonetracker-release-20110714-*"
      ]
  }
}
