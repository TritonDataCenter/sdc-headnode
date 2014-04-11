#!/usr/bin/bash
#
# Download and install all given images. Note that 'upgrade-all.sh' will do
# this lazily as required. This is here to pre-download all images for a faster
# upgrade of multiple roles.
#
# Usage:
#   ./download-all.sh <upgrade-images-file>
#

set -o xtrace
set -o errexit

IMAGE_LIST=$1
if [[ -z $1 ]]; then
    echo "$0: error: no '<update-images-file>' given"
    echo ""
    echo "Usage: download-all.sh <update-images-file>"
    exit 1
fi
source $IMAGE_LIST

[[ -n "$SDC_IMAGE" ]] && ./download-image.sh $SDC_IMAGE
[[ -n "$UFDS_IMAGE" ]] && ./download-image.sh $UFDS_IMAGE
[[ -n "$ADMINUI_IMAGE" ]] && ./download-image.sh $ADMINUI_IMAGE
[[ -n "$AMON_IMAGE" ]] && ./download-image.sh $AMON_IMAGE
[[ -n "$AMONREDIS_IMAGE" ]] && ./download-image.sh $AMONREDIS_IMAGE
[[ -n "$CA_IMAGE" ]] && ./download-image.sh $CA_IMAGE
[[ -n "$CLOUDAPI_IMAGE" ]] && ./download-image.sh $CLOUDAPI_IMAGE
[[ -n "$CNAPI_IMAGE" ]] && ./download-image.sh $CNAPI_IMAGE
[[ -n "$DHCPD_IMAGE" ]] && ./download-image.sh $DHCPD_IMAGE
[[ -n "$FWAPI_IMAGE" ]] && ./download-image.sh $FWAPI_IMAGE
[[ -n "$IMGAPI_IMAGE" ]] && ./download-image.sh $IMGAPI_IMAGE
[[ -n "$NAPI_IMAGE" ]] && ./download-image.sh $NAPI_IMAGE
[[ -n "$SAPI_IMAGE" ]] && ./download-image.sh $SAPI_IMAGE
[[ -n "$USAGEAPI_IMAGE" ]] && ./download-image.sh $USAGEAPI_IMAGE
[[ -n "$VMAPI_IMAGE" ]] && ./download-image.sh $VMAPI_IMAGE
[[ -n "$WORKFLOW_IMAGE" ]] && ./download-image.sh $WORKFLOW_IMAGE
[[ -n "$DAPI_IMAGE" ]] && ./download-image.sh $DAPI_IMAGE
[[ -n "$SDCSSO_IMAGE" ]] && ./download-image.sh $SDCSSO_IMAGE
[[ -n "$MORAY_IMAGE" ]] && ./download-image.sh $MORAY_IMAGE
[[ -n "$RABBITMQ_IMAGE" ]] && ./download-image.sh $RABBITMQ_IMAGE
[[ -n "$PAPI_IMAGE" ]] && ./download-image.sh $PAPI_IMAGE
[[ -n "$MAHI_IMAGE" ]] && ./download-image.sh $MAHI_IMAGE
