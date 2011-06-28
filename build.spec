{
    "platform-release": "develop"
  , "hvm-platform-release": "HVM"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.122"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "master"
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
  , "adminui-checkout": "origin/master"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-master-.*.tar.bz2$"
  , "capi-checkout": "origin/master"
  , "dhcpd-checkout": "origin/master"
  , "mapi-checkout": "origin/master"
  , "portal-checkout": "origin/master"
  , "cloudapi-checkout": "origin/master"
  , "pubapi-checkout": "origin/master"
  , "rabbitmq-checkout": "origin/master"
  , "upgrades": {
      "agents": [
          "atropos/master/atropos-master-*"
        , "cloud_analytics/master/cabase-master-*"
        , "cloud_analytics/master/cainstsvc-master-*"
        , "dataset_manager/master/dataset_manager-master-*"
        , "heartbeater/master/heartbeater-master-*"
        , "provisioner/master/provisioner-master-*"
        , "smartlogin/master/smartlogin-master-*"
        , "zonetracker/master/zonetracker-master-*"
      ]
  }
}
