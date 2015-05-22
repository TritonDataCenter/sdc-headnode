{
  "vmware_version": 5,
  "build-tgz": "true",
  "coal-memsize": 4096,
  "coal-enable-serial": true,
  "// joyent-build": "set to true to enable ancillary repository use",

  "features": {
    "debug-platform": {
      "enabled": false,
      "env": "DEBUG_BUILD"
    },
    "joyent-build": {
      "enabled": false,
      "env": "JOYENT_BUILD"
    }
  },

  "bits-branch": "master",

  "// manta-*": "You can override these in your build.spec.local.",
  "manta-base-path": "/Joyent_Dev/public/builds",
  "joyent-manta-base-path": "/Joyent_Dev/stor/builds",
  "manta-user": "Joyent_Dev",
  "manta-url": "https://us-east.manta.joyent.com",

  "zones": {
    "adminui": {},
    "amon": {},
    "amonredis": {},
    "assets": {},
    "binder": {},
    "ca": {},
    "cloudapi": {},
    "cnapi": {},
    "dhcpd": {},
    "fwapi": {},
    "imgapi": {},
    "mahi": {},
    "manatee": {
      "jobname": "sdc-manatee"
    },
    "manta": {
      "jobname": "manta-deployment"
    },
    "moray": {},
    "napi": {},
    "papi": {},
    "rabbitmq": {},
    "redis": {},
    "sapi": {},
    "sdc": {},
    "ufds": {},
    "vmapi": {},
    "workflow": {}
  },

  "files": {
    "sdcboot": {
      "file": { "base": "sdcboot", "ext": "tgz" }
    },

    "platboot": {
      "jobname": "platform",
      "if_not_feature": "debug-platform",
      "file": { "base": "boot", "ext": "tgz" }
    },
    "platform": {
      "if_not_feature": "debug-platform",
      "file": { "base": "platform", "ext": "tgz" }
    },

    "platboot-debug": {
      "jobname": "platform-debug",
      "if_feature": "debug-platform",
      "file": { "base": "boot-debug", "ext": "tgz" }
    },
    "platform-debug": {
      "if_feature": "debug-platform",
      "file": { "base": "platform-debug", "ext": "tgz" }
    },

    "sdcadm": {
      "file": { "base": "sdcadm", "ext": "sh" }
    },

    "agents": {
      "jobname": "agentsshar",
      "file": { "base": "agents", "ext": "sh" }
    },
    "agents_md5": {
      "jobname": "agentsshar",
      "file": { "base": "agents", "ext": "md5sum" }
    },

    "firmware-tools": {
      "if_feature": "joyent-build",
      "alt_manta_base": "joyent-manta-base-path",
      "file": { "base": "firmware-tools", "ext": "tgz" }
    }
  },

  "images": {
    "smartos-1.6.3": {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-smartos",
      "version": "1.6.3",
      "uuid": "fd2cc906-8938-11e3-beab-4359c665ac99"
    },
    "multiarch-13.3.1": {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-multiarch",
      "version": "13.3.1",
      "uuid": "b4bdc598-8939-11e3-bea4-8341f6861379"
    },
    "base64-13.3.1": {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-base64",
      "version": "13.3.1",
      "uuid": "aeb4e3e0-8937-11e3-b0bd-637363a89e49"
    },
    "base-14.2.0": {
      "imgapi": "https://updates.joyent.com",
      "name": "sdc-base",
      "version": "14.2.0",
      "uuid": "de411e86-548d-11e4-a4b7-3bb60478632a"
    }
  }
}
