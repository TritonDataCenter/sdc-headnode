{
    "platform-release": "20110826T212040Z"
  , "hvm-platform-release": "HVM"
  , "hvm-subdir": "release-20110714"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.138"
  , "build-tgz": "true"
  , "build-hvm": "false"
  , "agents-shar": "release-20110825"
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
  , "adminui-checkout": "origin/release-20110825"
  , "ca-tarball": "^ca-pkg-release-20110825-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110825"
  , "dhcpd-checkout": "origin/release-20110825"
  , "mapi-checkout": "origin/release-20110825"
  , "portal-checkout": "origin/release-20110825"
  , "cloudapi-checkout": "origin/release-20110825"
  , "rabbitmq-checkout": "origin/release-20110825"
  , "sdc-webinfo-checkout": "origin/release-20110825"
  , "upgrades": {
      "agents": [
          "cloud_analytics/release-20110825/cabase-release-20110825-*"
        , "cloud_analytics/release-20110825/cainstsvc-release-20110825-*"
        , "dataset_manager/release-20110825/dataset_manager-release-20110825-*"
        , "heartbeater/release-20110825/heartbeater-release-20110825-*"
        , "provisioner-v2/release-20110825/provisioner-v2-release-20110825-*"
        , "smartlogin/release-20110825/smartlogin-release-20110825-*"
        , "zonetracker/release-20110825/zonetracker-release-20110825-*"
        , "zonetracker-v2/release-20110825/zonetracker-v2-release-20110825-*"
      ]
  }
}
