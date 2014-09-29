{
  "build-tgz": "true",
  "coal-memsize": 4096,
  "coal-enable-serial": true,
  "// joyent-build": "set to true to enable ancillary repository use",

  "bits-branch": "master",
  "platform-release": "master",
  "agents-shar": "master",
  "sdcboot-release": "master",
  "firmware-tools-release": "master",
  "sdcadm-release": "master",

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
  "dhcpd-image": "dhcpd/dhcpd-zfs-.*manifest",
  "fwapi-image": "fwapi/fwapi-zfs-.*manifest",
  "imgapi-image": "imgapi/imgapi-zfs-.*manifest",
  "loadbalancer-image": "muppet/muppet-zfs-.*manifest",
  "mahi-image": "mahi/mahi-zfs-.*manifest",
  "manatee-image": "sdc-manatee/sdc-manatee-zfs-.*manifest",
  "manta-image": "manta-deployment/manta-deployment-zfs-.*manifest",
  "moray-image": "moray/moray-zfs-.*manifest",
  "napi-image": "napi/napi-zfs-.*manifest",
  "papi-image": "papi/papi-zfs-.*manifest",
  "rabbitmq-image": "rabbitmq/rabbitmq-zfs-.*manifest",
  "redis-image": "redis/redis-zfs-.*manifest",
  "sapi-image": "sapi/sapi-zfs-.*manifest",
  "sdc-image": "sdc/sdc-zfs-.*manifest",
  "ufds-image": "ufds/ufds-zfs-.*manifest",
  "vmapi-image": "vmapi/vmapi-zfs-.*manifest",
  "workflow-image": "workflow/workflow-zfs-.*manifest",

  "datasets": [
    {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-smartos-1.6.3",
      "uuid": "fd2cc906-8938-11e3-beab-4359c665ac99"
    }, {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-multiarch-13.3.1",
      "uuid": "b4bdc598-8939-11e3-bea4-8341f6861379"
    }, {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-base64-1.3.1",
      "uuid": "aeb4e3e0-8937-11e3-b0bd-637363a89e49"
    }
  ]
}
