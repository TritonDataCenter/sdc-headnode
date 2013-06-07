#!/usr/bin/bash
#
# download-all.sh: download and install all images

set -o xtrace
set -o errexit

source ./images.sh

./download-image.sh $ADMINUI_IMAGE
./download-image.sh $AMON_IMAGE
./download-image.sh $CA_IMAGE
./download-image.sh $CLOUDAPI_IMAGE
./download-image.sh $CNAPI_IMAGE
./download-image.sh $DAPI_IMAGE
./download-image.sh $DHCPD_IMAGE
./download-image.sh $FWAPI_IMAGE
./download-image.sh $IMGAPI_IMAGE
./download-image.sh $NAPI_IMAGE
./download-image.sh $REDIS_IMAGE
./download-image.sh $SAPI_IMAGE
./download-image.sh $USAGEAPI_IMAGE
./download-image.sh $VMAPI_IMAGE
./download-image.sh $WORKFLOW_IMAGE
