#!/bin/bash
# Setup this server for provisioning protemplate SmartMachines.
#
# WARNINGS:
#
# - DO NOT USE IN PRODUCTION.
#

set -o errexit      # crash on errors
set -o pipefail     # crash on errors in pipelines
#set -o xtrace       # debugging output


DATASET_NAME=protemplate-2.5.2
DATASET_BASE=$(echo $DATASET_NAME | awk -F'-' '{print $1}')
ASSETS_JOYENT_US_IP=$(dig @8.8.8.8 assets.joyent.us +short)
DATASET_RELEASES="https://guest:GrojhykMid@${ASSETS_JOYENT_US_IP}/templates"


# Get the dataset.
if [[ `zfs list -H -o name zones/$DATASET_NAME 2>/dev/null` != "zones/$DATASET_NAME" ]]; then
  dataset_usbkey_path=/usbkey/${DATASET_BASE}.zfs.bz2
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


echo
echo "You should be ready to provision '${DATASET_BASE}' SmartMachines on this server."
