{
  "build-tgz": "true",
  "coal-memsize": 4096,
  "coal-enable-serial": true,

  "bits-url": "https://bits.joyent.us/builds",
  "bits-url-open": "http://stuff:kie7Ooph@stuff.smartdatacenter.org",
  "bits-branch": "master",
  "platform-release": "master",
  "agents-shar": "master",
  "sdcboot-release": "master",
  "firmware-tools-release": "master",

  "use-images": true,

  "// *-tarball": "If adding to this list, you must also update mountain-gorilla.git/build.spec.in accordingly",
  "amon-tarball": "amon/amon-pkg-master-.*.tar.bz2",
  "imgapi-cli-tarball": "imgapi-cli/imgapi-cli-pkg-master-.*.tar.bz2",

  "// *-image": "If adding to this list, you must also update mountain-gorilla.git/build.spec.in accordingly",
  "adminui-image": "adminui/adminui-zfs-.*manifest",
  "amon-image": "amon/amon-zfs-.*manifest",
  "assets-image": "assets/assets-zfs-.*manifest",
  "binder-image": "binder/binder-zfs-.*manifest",
  "ca-image": "ca/ca-zfs-.*manifest",
  "cloudapi-image": "cloudapi/cloudapi-zfs-.*manifest",
  "cnapi-image": "cnapi/cnapi-zfs-.*manifest",
  "dapi-image": "dapi/dapi-zfs-.*manifest",
  "dhcpd-image": "dhcpd/dhcpd-zfs-.*manifest",
  "fwapi-image": "fwapi/fwapi-zfs-.*manifest",
  "imgapi-image": "imgapi/imgapi-zfs-.*manifest",
  "keyapi-image": "keyapi/keyapi-zfs-.*manifest",
  "manatee-image": "manatee/manatee-zfs-.*manifest",
  "manta-image": "manta-deployment/manta-deployment-zfs-.*manifest",
  "moray-image": "moray/moray-zfs-.*manifest",
  "napi-image": "napi/napi-zfs-.*manifest",
  "rabbitmq-image": "rabbitmq/rabbitmq-zfs-.*manifest",
  "redis-image": "redis/redis-zfs-.*manifest",
  "sapi-image": "sapi/sapi-zfs-.*manifest",
  "sdcsso-image": "sdcsso/sdcsso-zfs-.*manifest",
  "ufds-image": "ufds/ufds-zfs-.*manifest",
  "usageapi-image": "usageapi/usageapi-zfs-.*manifest",
  "vmapi-image": "vmapi/vmapi-zfs-.*manifest",
  "workflow-image": "workflow/workflow-zfs-.*manifest",

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
