{
    "platform-release": "20110802T190624Z"
  , "hvm-platform-release": "HVM-20110726T001212Z"
  , "use-proxy": "false"
  , "proxy-ip": "10.0.1.138"
  , "build-tgz": "true"
  , "build-hvm": "true"
  , "agents-shar": "release-20110714-20110815T191053Z"
  , "hvm-agents-shar": "hvm-20110726T001206Z"
  , "datasets": [
      { "name": "smartos-1.3.15"
      , "uuid": "184c9b38-ad3d-11e0-bad6-1b7240aaa5fc"
      , "headnode_zones": "true"
      }
    , { "name": "hostrouter-0.0.3"
      , "uuid": "c9fce11a-c9cd-11e0-a6e0-dfa49f484f3c"
      , "url": "https://guest:GrojhykMid@216.57.203.68/stuff/isaacs/hostrouter/hostrouter-0.0.3.zfs.bz2"
      }
    , { "name": "nodejs-1.2.1"
      , "uuid": "c07e7660-c92f-11e0-8078-7373122f78d0"
      , "url": "https://guest:GrojhykMid@216.57.203.68/stuff/isaacs/nodejs/nodejs-1.2.1.zfs.bz2"
      }
  ]
  , "adminui-checkout": "origin/release-20110714"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-release-20110714-.*.tar.bz2$"
  , "capi-checkout": "origin/release-20110714"
  , "dhcpd-checkout": "origin/release-20110714"
  , "mapi-checkout": "origin/release-20110714"
  , "portal-checkout": "origin/lime-node"
  , "cloudapi-checkout": "origin/lime-node"
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
        , "zonetracker-v2/release-20110714/zonetracker-v2-release-20110714-*"
      ]
  }
}
