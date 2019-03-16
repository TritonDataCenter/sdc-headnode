{
  "vmware_version": 7,
  "build-tgz": "true",
  "coal-memsize": 8192,
  "coal-enable-serial": true,
  "no-rabbit": true,
  "clean-cache": true,
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
    "platimages": {
      "jobname": "platform",
      "if_not_feature": "debug-platform",
      "file": { "base": "images", "ext": "tgz" }
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
    "platimages-debug": {
      "jobname": "platform-debug",
      "if_feature": "debug-platform",
      "file": { "base": "images-debug", "ext": "tgz" }
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
  }
}
