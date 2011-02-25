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

source /lib/sdc/config.sh
load_sdc_config


DATASET_NAME=nodejs-0.4.0
DATASET_BASE=$(echo $DATASET_NAME | awk -F'-' '{print $1}')
DATASET_RELEASES="http://${CONFIG_assets_admin_ip}/datasets"
NODE_SERVICE_RELEASES="http://${CONFIG_assets_admin_ip}/datasets"


# Get the dataset.
if [[ `zfs list -H -o name zones/$DATASET_NAME 2>/dev/null` != "zones/$DATASET_NAME" ]]; then
  dataset_usbkey_path=/usbkey/datasets/${DATASET_BASE}.zfs.bz2
  if [[ -e "$dataset_usbkey_path" ]]; then
    dataset_path=$dataset_usbkey_path
  else
    dataset_url=${DATASET_RELEASES}/${DATASET_NAME}.zfs.bz2
    echo "==> Downloading ${dataset_url}"
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
  (cd /tmp && tar xzf ${latest})
  base=$(echo ${latest} | sed 's/\.tgz$//')
  mv /tmp/${base} /opt/nodejs
else
  echo "Already have node service bits (/opt/nodejs)."
  echo "Note: 'rm -rf /opt/nodejs' and re-run to get the latest node service."
fi


echo
echo "You should be ready to provision '${DATASET_BASE}' SmartMachines on this server."
