#!/usr/bin/bash
#
# Copyright (c) 2014, Joyent, Inc. All rights reserved.
#
# Script to add "mahi" zone to existing SDC 7 setups
# You can either add latest available image at updates-imgadm:
#
#     ./add-zk.sh
#
# or specify an image uuid/version as follows:
#
#   ./add-zk.sh d7a36bca-4fdd-466f-9086-a2a22447c257 sdc-zookeeper-zfs-master-20130711T073353Z-g7dcddeb
#
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit

role=zookeeper

# Get SDC Application UUID from SAPI
SDC_APP_UUID=$(sdc-sapi --no-headers /applications?name=sdc|json 0.uuid)

NEW_IMAGE=$1
NEW_VERSION=$2

if [[ ! -n $NEW_IMAGE ]]; then
  echo "getting image details from updates-imgadm"
  # Get latest image details from updates-imgadm
  ary=($(updates-imgadm list name=sdc-zookeeper -o uuid,name,version | tail -1))
  NEW_IMAGE=${ary[0]}
  NEW_VERSION="${ary[1]}-zfs-${ary[2]}"
else
  echo "Using the provided IMAGE UUID and VERSION"
fi

# Grab image manifest and file from updates-imgadm:
MANIFEST_TMP="$NEW_VERSION.imgmanifest.tmp"
MANIFEST="$NEW_VERSION.imgmanifest"

IMG_FILE="$NEW_VERSION.gz"
ADMIN_UUID=$(sdc-sapi --no-headers /applications?name=sdc | json -Ha metadata.ufds_admin_uuid)

IS_IMAGE_IMPORTED=$(sdc-imgadm list -o uuid name=sdc-zookeeper | grep $NEW_IMAGE || true)

if [[ -n "$IS_IMAGE_IMPORTED" ]]; then
  echo "Image is already imported, moving into next step"
else
  # Get the original manifest
  if [[ ! -e /var/tmp/$MANIFEST_TMP ]]; then
    echo "Fetching image manifest"
    updates-imgadm get "$NEW_IMAGE" > "$MANIFEST_TMP"
    json -f $MANIFEST_TMP -e "this.owner=\"$ADMIN_UUID\"" > $MANIFEST
  else
    echo "Image Manifest already downloaded, moving into next step"
  fi

  if [[ ! -e /var/tmp/$IMG_FILE ]]; then
    # Get the new image file:
    updates-imgadm get-file $NEW_IMAGE > $IMG_FILE
  else
    echo "Image file already downloaded, moving into next step"
  fi

  echo "Importing image"
  # Import the new image
  sdc-imgadm import -m $MANIFEST -f $IMG_FILE
fi

DOMAIN=$(sdc-sapi /applications?name=sdc | json -Ha metadata.datacenter_name).$(sdc-sapi /applications?name=sdc | json -Ha metadata.dns_domain)
USERSCRIPT=$(/usr/node/bin/node -e 'console.log(JSON.stringify(require("fs").readFileSync("/usbkey/default/user-script.common", "utf8")))')

# Before attempting to create the service, let's double check it doesn't exist:
SERVICE_UUID=$(sdc-sapi --no-headers /services?name=$role | json -Ha uuid)

if [[ -n "$SERVICE_UUID" ]]; then
  echo "Service $role already exists, moving into next step"
else
  json -f ./sapi/$role/"${role}"_svc.json \
    | json -e "this.application_uuid=\"$SDC_APP_UUID\"" \
    | json -e "this.metadata.SERVICE_DOMAIN=\"zookeeper.${DOMAIN}\"" \
    | json -e "this.params.image_uuid=\"$NEW_IMAGE\"" \
    | json -e "this.metadata[\"user-script\"]=$USERSCRIPT" \
    >./"${role}"-service.json

  echo "Service $role does not exist. Attempting to create it"
  SERVICE_UUID=$(sdc-sapi /services -X POST -d@./"${role}"-service.json | json -H uuid)
  echo "Service UUID is '$SERVICE_UUID'"

  cat <<EOM > ./update-sdc-app.json
{
    "metadata" : {
        "ZOOKEEPER_SERVICE" : "zookeeper.$DOMAIN",
        "zookeeper_domain" : "zookeeper.$DOMAIN"
    }
}
EOM
  sapiadm update $SDC_APP_UUID -f ./update-sdc-app.json
fi

echo "Zookeeper service installed & ready for provisioning."
exit 0
