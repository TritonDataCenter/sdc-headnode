#!/bin/bash
# Setup this server for provisioning nodejs SmartMachines.
#
# Currently this means:
# - 'zfs recv' the nodejs dataset (downloading it if necessary, i.e. on non-headnode).
# - get the "node service" bits into "/opt/nodejs"
#
# WARNINGS:
#
# - DO NOT USE IN PRODUCTION.
#

set -o errexit      # crash on errors
set -o pipefail     # crash on errors in pipelines
#set -o xtrace       # debugging output


DATASET_NAME=nodejs-0.4.0
DATASET_BASE=$(echo $DATASET_NAME | awk -F'-' '{print $1}')
ASSETS_JOYENT_US_IP=$(dig @8.8.8.8 assets.joyent.us +short)
DATASET_RELEASES="https://guest:GrojhykMid@${ASSETS_JOYENT_US_IP}/templates"
COAL_JOYENT_US_IP=$(dig @8.8.8.8 coal.joyent.us +short)
NODE_SERVICE_RELEASES="https://guest:GrojhykMid@${COAL_JOYENT_US_IP}/coal/live_147/node"


# Get the dataset.
if [[ `zfs list -H -o name zones/$DATASET_NAME 2>/dev/null` != "zones/$DATASET_NAME" ]]; then
  dataset_usbkey_path=/usbkey/datasets/${DATASET_BASE}.zfs.bz2
  if [[ -e "$dataset_usbkey_path" ]]; then
    dataset_path=$dataset_usbkey_path
  else
    dataset_url=${DATASET_RELEASES}/${DATASET_NAME}.zfs.bz2
    echo "Downloading '$DATASET_NAME' from assets.joyent.us."
    (cd /tmp && curl --progress-bar -k -O ${dataset_url})
    dataset_path=/tmp/${DATASET_NAME}.zfs.bz2
  fi
  echo "Load 'zone/$DATASET_NAME' dataset (from ${dataset_path})."
  bzcat ${dataset_path} | zfs receive -e zones || exit 1;
else
  echo "Already have '$DATASET_NAME' dataset."
fi


# Get the node service bits into "/opt/nodejs".
if [[ ! -e "/opt/nodejs" ]]; then
  latest=$(curl -k -sS ${NODE_SERVICE_RELEASES}/ \
          | grep "href=\"node_service-" | cut -d'"' -f2 | sort | tail -n 1)
  echo "Getting latest node_service build ($latest)."
  echo "==> Downloading ${latest}"
  (cd /tmp && curl --progress-bar -k -O ${NODE_SERVICE_RELEASES}/${latest})
  echo "==> Extract to '/opt/nodejs'"
  (cd /opt && tar xzf /tmp/${latest})
else
  echo "Already have node service bits (/opt/nodejs)."
  echo "Note: 'rm -rf /opt/nodejs' and re-run to get the latest node service."
fi


echo
echo "You should be ready to provision '${DATASET_BASE}' SmartMachines on this server."
