{
    "platform-release": "master"
  , "hvm-platform-release": "HVM"
  , "hvm-subdir": "release-20110714"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.138"
  , "build-tgz": "true"
  , "build-hvm": "false"
  , "agents-shar": "master"
  , "hvm-agents-shar": "hvm"
  , "datasets": [
      { "name": "smartos-1.3.17"
      , "uuid": "bb6d5a10-c330-11e0-8f18-9fbfcd26660b"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.7"
      , "uuid": "e173ecd7-4809-4429-af12-5d11bcc29fd8"
      }
  ]
  , "adminui-checkout": "origin/master"
  , "ca-tarball": "^ca-pkg-master-.*.tar.bz2$"
  , "capi-checkout": "origin/master"
  , "dhcpd-checkout": "origin/master"
  , "mapi-checkout": "origin/master"
  , "portal-checkout": "origin/master"
  , "cloudapi-checkout": "origin/master"
  , "rabbitmq-checkout": "origin/master"
  , "sdc-webinfo-checkout": "origin/master"
  , "upgrades": {
      "agents": [
          "cloud_analytics/master/cabase-master-*"
        , "cloud_analytics/master/cainstsvc-master-*"
        , "dataset_manager/master/dataset_manager-master-*"
        , "heartbeater/master/heartbeater-master-*"
        , "provisioner-v2/master/provisioner-v2-master-*"
        , "smartlogin/master/smartlogin-master-*"
        , "zonetracker/master/zonetracker-master-*"
        , "zonetracker-v2/master/zonetracker-v2-master-*"
      ]
  }
}
