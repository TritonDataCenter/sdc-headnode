{
    "platform-release": "20110526T190646Z"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "hvm-agents": "https://guest:GrojhykMid@216.57.203.66:444/coal/hvm/agents-hvm-20110526T182727Z.sh"
  , "hvm-platform": "https://guest:GrojhykMid@216.57.203.66:444/coal/hvm/platform-HVM-20110526T182732Z.tgz"
  , "agents-shar": "release-20110526-20110526T211741Z"
  , "datasets": [
      { "name": "smartos-1.3.13"
      , "uuid": "63ce06d8-7ae7-11e0-b0df-1fcf8f45c5d5"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.1"
      , "uuid": "b66fb52a-6a8a-11e0-94cd-b347300c5a06"
      }
  ]
  , "adminui-checkout": "origin/release-20110526"
  , "atropos-tarball":"^atropos-develop-20110210.tar.bz2.20110224$" 
  , "ca-tarball": "^ca-pkg-release-20110526-20110526.tar.bz2$"
  , "capi-checkout": "origin/release-20110526"
  , "dhcpd-checkout": "origin/release-20110526"
  , "mapi-checkout": "origin/release-20110526"
  , "portal-checkout": "origin/release-20110526"
  , "cloudapi-checkout": "origin/release-20110526"
  , "pubapi-checkout": "origin/release-20110526"
  , "rabbitmq-checkout": "origin/release-20110526"
  , "upgrades": {
      "agents": [
          "atropos/develop/atropos-release-20110526-*"
        , "cloud_analytics/master/cabase-release-20110526-*"
        , "cloud_analytics/master/cainstsvc-release-20110526-*"
        , "dataset_manager/develop/dataset_manager-release-20110526-*"
        , "heartbeater/develop/heartbeater-release-20110526-*"
        , "provisioner/develop/provisioner-release-20110526-*"
        , "smartlogin/develop/smartlogin-release-20110526-*"
        , "zonetracker/develop/zonetracker-release-20110526-*"
      ]
  }
}
