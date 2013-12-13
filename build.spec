{
  "build-tgz": "true",
  "coal-memsize": 4096,
  "coal-enable-serial": true,

  "bits-branch": "master",
  "platform-release": "master",
  "agents-shar": "master",
  "sdcboot-release": "master",
  "firmware-tools-release": "master",

  "use-images": true,

  "// manta-*": "You can override these in your build.spec.local.",
  "manta-base-path": "/Joyent_Dev/stor/builds",
  "manta-user": "Joyent_Dev",
  "manta-url": "https://us-east.manta.joyent.com",

  "// *-image": "If adding to this list, you must also update mountain-gorilla.git/build.spec.in accordingly",
  "adminui-image": "adminui/adminui-zfs-.*manifest",
  "amon-image": "amon/amon-zfs-.*manifest",
  "amonredis-image": "amonredis/amonredis-zfs-.*manifest",
  "assets-image": "assets/assets-zfs-.*manifest",
  "binder-image": "binder/binder-zfs-.*manifest",
  "ca-image": "ca/ca-zfs-.*manifest",
  "cloudapi-image": "cloudapi/cloudapi-zfs-.*manifest",
  "cnapi-image": "cnapi/cnapi-zfs-.*manifest",
  "dapi-image": "dapi/dapi-zfs-.*manifest",
  "dhcpd-image": "dhcpd/dhcpd-zfs-.*manifest",
  "fwapi-image": "fwapi/fwapi-zfs-.*manifest",
  "imgapi-image": "imgapi/imgapi-zfs-.*manifest",
  "manatee-image": "manatee/manatee-zfs-.*manifest",
  "manta-image": "manta-deployment/manta-deployment-zfs-.*manifest",
  "moray-image": "moray/moray-zfs-.*manifest",
  "napi-image": "napi/napi-zfs-.*manifest",
  "papi-image": "papi/papi-zfs-.*manifest",
  "rabbitmq-image": "rabbitmq/rabbitmq-zfs-.*manifest",
  "redis-image": "redis/redis-zfs-.*manifest",
  "sapi-image": "sapi/sapi-zfs-.*manifest",
  "sdc-image": "sdc/sdc-zfs-.*manifest",
  "sdcsso-image": "sdcsso/sdcsso-zfs-.*manifest",
  "ufds-image": "ufds/ufds-zfs-.*manifest",
  "vcapi-image": "vcapi/vcapi-zfs-.*manifest",
  "vmapi-image": "vmapi/vmapi-zfs-.*manifest",
  "workflow-image": "workflow/workflow-zfs-.*manifest",

  "datasets": [
    {
      "name": "smartos-1.6.3",
      "uuid": "01b2c898-945f-11e1-a523-af1afbe22822",
      "pkgsrc": "2011Q4",
      "pkgsrc_url": "http://pkgsrc.joyent.com/sdc/2011Q4/gcc46/All/"
    }
  ]
}
