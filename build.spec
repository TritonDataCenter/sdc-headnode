{
    "platform-release": "20110811"
  , "hvm-platform-release": "HVM"
  , "hvm-subdir": "release-20110811"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.138"
  , "master-url": "https://guest:GrojhykMid@216.57.203.68/coal/releases/2011-08-11/deps/"
  , "build-tgz": "true"
  , "build-hvm": "false"
  , "agents-shar": "release-20110811-20110811T235329Z"
  , "hvm-agents-shar": "hvm"
  , "datasets": [
      { "name": "smartos-1.3.17"
      , "uuid": "bb6d5a10-c330-11e0-8f18-9fbfcd26660b"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.6"
      , "uuid": "2214e5f8-4e5d-2a4f-8f72-c4599daa1d28"
      }
  ]
  , "adminui-checkout": "origin/release-20110811"
  , "ca-tarball": "^ca-pkg-release-20110811-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110811"
  , "dhcpd-checkout": "origin/release-20110811"
  , "mapi-checkout": "origin/release-20110811"
  , "portal-checkout": "origin/release-20110811"
  , "cloudapi-checkout": "origin/release-20110811"
  , "rabbitmq-checkout": "origin/release-20110811"
  , "upgrades": {
      "agents": [
          "cloud_analytics/release-20110811/cabase-release-20110811-*"
        , "cloud_analytics/release-20110811/cainstsvc-release-20110811-*"
        , "dataset_manager/release-20110811/dataset_manager-release-20110811-*"
        , "heartbeater/release-20110811/heartbeater-release-20110811-*"
        , "provisioner/release-20110811/provisioner-release-20110811-*"
        , "smartlogin/release-20110811/smartlogin-release-20110811-*"
        , "zonetracker/release-20110811/zonetracker-release-20110811-*"
      ]
  }
}
