{
    "platform-release": "20110609T175508Z"
  , "hvm-platform-release": "HVM"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.122"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "release-20110609-20110610T065825Z"
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
  , "adminui-checkout": "origin/release-20110609"
  , "atropos-tarball": "^atropos-develop-20110210.tar.bz2.20110224$"
  , "ca-tarball": "^ca-pkg-release-20110609-20110609.tar.bz2$"
  , "capi-checkout": "origin/release-20110609"
  , "dhcpd-checkout": "origin/release-20110609"
  , "mapi-checkout": "origin/release-20110609"
  , "portal-checkout": "origin/release-20110609"
  , "cloudapi-checkout": "origin/release-20110609"
  , "pubapi-checkout": "origin/release-20110609"
  , "rabbitmq-checkout": "origin/release-20110609"
  , "upgrades": {
      "agents": [
          "atropos/release-20110609/atropos-release-20110609-*"
	, "cloud_analytics/release-20110609/cabase-release-20110609-*"
	, "cloud_analytics/release-20110609/cainstsvc-release-20110609-*"
        , "dataset_manager/release-20110609/dataset_manager-release-20110609-*"
        , "heartbeater/release-20110609/heartbeater-*"
        , "provisioner/release-20110609/provisioner-release-20110609-*"
        , "smartlogin/develop/smartlogin-release-20110609-*"
        , "zonetracker/release-20110609/zonetracker-release-20110609-*"
      ]
  }
}
