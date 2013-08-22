#!/usr/bin/bash
#
# download-all.sh: download and install all images

set -o xtrace
set -o errexit

IMAGE_LIST=$1
if [[ -z $1 ]]; then
    fatal "Usage: upgrade-all.sh imagefile.sh"
fi
source $IMAGE_LIST

./download-image.sh $SDC_IMAGE
# ./download-image.sh $UFDS_IMAGE
# ./download-image.sh $ADMINUI_IMAGE
# ./download-image.sh $AMON_IMAGE
# ./download-image.sh $AMONREDIS_IMAGE
# ./download-image.sh $CA_IMAGE
./download-image.sh $CLOUDAPI_IMAGE
./download-image.sh $CNAPI_IMAGE

# ./download-image.sh $DHCPD_IMAGE
# ./download-image.sh $FWAPI_IMAGE
./download-image.sh $IMGAPI_IMAGE
# ./download-image.sh $NAPI_IMAGE
# ./download-image.sh $SAPI_IMAGE
# ./download-image.sh $USAGEAPI_IMAGE
./download-image.sh $VMAPI_IMAGE
./download-image.sh $WORKFLOW_IMAGE

./download-image.sh $DAPI_IMAGE
