{
  "build-tgz": "true",
  "bits-url": "https://stuff.joyent.us/stuff/builds",
  "bits-url-open": "http://stuff:kie7Ooph@stuff.smartdatacenter.org",
  "bits-branch": "master",
  "platform-release": "master",
  "agents-shar": "master",
  "sdcboot-release": "master",

  "use-images": false,
  "updates_url": "https://updates.joyent.us",

  "// *-tarball": "If adding to this list, you must also update mountain-gorilla.git/build.spec.in accordingly",
  "adminui-tarball": "adminui/adminui-pkg-master-.*.tar.bz2",
  "amon-tarball": "amon/amon-pkg-master-.*.tar.bz2",
  "assets-tarball": "assets/assets-pkg-master-.*.tar.bz2",
  "ca-tarball": "ca/ca-pkg-master-.*.tar.bz2",
  "cloudapi-tarball": "cloudapi/cloudapi-pkg-master-.*.tar.bz2",
  "cnapi-tarball": "cnapi/cnapi-pkg-master-.*.tar.bz2",
  "dapi-tarball": "dapi/dapi-pkg-master-.*.tar.bz2",
  "dhcpd-tarball": "dhcpd/dhcpd-pkg-master-.*.tar.bz2",
  "fwapi-tarball": "fwapi/fwapi-pkg-master-.*.tar.bz2",
  "imgapi-tarball": "imgapi/imgapi-pkg-master-.*.tar.bz2",
  "imgapi-cli-tarball": "imgapi-cli/imgapi-cli-pkg-master-.*.tar.bz2",
  "keyapi-tarball": "keyapi/keyapi-pkg-master-.*.tar.bz2",
  "manatee-tarball": "manatee/manatee-pkg-master-.*.tar.bz2",
  "manta-tools": "manta/manta-pkg-master-.*.tar.bz2",
  "manta-tarball": "manta-deployment/manta-deployment-pkg-master-.*.tar.bz2",
  "moray-tarball": "moray/moray-pkg-master-.*.tar.bz2",
  "napi-tarball": "napi/napi-pkg-master-.*.tar.bz2",
  "rabbitmq-tarball": "rabbitmq/rabbitmq-pkg-master-.*.tar.bz2",
  "redis-tarball": "redis/redis-pkg-master-.*.tar.bz2",
  "sapi-tarball": "sapi/sapi-pkg-master-.*.tar.bz2",
  "sdcsso-tarball": "sdcsso/sdcsso-pkg-master-.*.tar.bz2",
  "ufds-tarball": "ufds/ufds-pkg-master-.*.tar.bz2",
  "usageapi-tarball": "usageapi/usageapi-pkg-master-.*.tar.bz2",
  "vmapi-tarball": "vmapi/vmapi-pkg-master-.*.tar.bz2",
  "workflow-tarball": "workflow/workflow-pkg-master-.*.tar.bz2",
  "zookeeper-tarball": "binder/binder-pkg-master-.*.tar.bz2",

  "manatee-image": {
    "name": "manta-postgres",
    "pattern": "master"
  },
  "moray-image": {
    "name": "manta-moray",
    "pattern": "master"
  },
  "zookeeper-image": {
    "name": "manta-nameservice",
    "pattern": "master"
  },

  "datasets": [
    {
      "name": "smartos-1.6.3",
      "uuid": "01b2c898-945f-11e1-a523-af1afbe22822",
      "pkgsrc": "2011Q4",
      "pkgsrc_url": "http://pkgsrc.joyent.com/sdc/2011Q4/gcc46/All/"
    },
    {
      "name": "multiarch-12.4.1",
      "uuid": "ee1fb198-5fe1-11e2-9cce-e319fd47df7b",
      "manifest_url": "http://pkgsrc.smartos.org/datasets/multiarch-12.4.1.dsmanifest",
      "file_url": "http://pkgsrc.smartos.org/datasets/multiarch-12.4.1.zfs.bz2",
      "pkgsrc": "2012Q4-multiarch",
      "pkgsrc_url": "http://pkgsrc.smartos.org/packages/SmartOS/2012Q4-multiarch/All"
    }
  ]
}
