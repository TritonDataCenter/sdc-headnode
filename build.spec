{
  "vmware_version": 7,
  "build-tgz": "true",
  "coal-memsize": 8192,
  "coal-enable-serial": true,
  "no-rabbit": true,
  "clean-cache": true,
  "smt_enabled": true,

  "features": {
    "debug-platform": {
      "enabled": false,
      "env": "DEBUG_BUILD"
    }
  },

  "bits-branch": "master",

  "manta-base-path": "/Joyent_Dev/public/builds",
  "manta-user": "Joyent_Dev",
  "manta-url": "https://us-central.manta.mnx.io",

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
    "ipxe": {
      "file": { "base": "ipxe", "ext": "tar.gz" }
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
    }
  }
}
