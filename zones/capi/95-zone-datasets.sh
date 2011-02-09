echo "95 configuring capi datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# capi-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/capi-data zones/capi/data
# capi-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/capi-app-timestamp)
zfs set mountpoint=/opt/smartdc/capi "zones/capi/app-$STAMP"
# Get git revision:
cd /opt/smartdc/capi-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into capi:
cd /opt/smartdc/capi-repo

if [[ "${IMG_TYPE}" == "coal" ]]; then
  cp -R ./ /opt/smartdc/capi
else
  /opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/capi/
fi

# Export only config into capi-data:
cd /opt/smartdc/capi-repo
# /opt/local/bin/git checkout-index -f --prefix=/opt/smartdc/capi-data/ config/
# Create some directories into capi-data
mkdir -p /opt/smartdc/capi-data/log
mkdir -p /opt/smartdc/capi-data/tmp/pids
# Remove and symlink directories:
mv /opt/smartdc/capi/config /opt/smartdc/capi-data/config
rm -Rf /opt/smartdc/capi/log
rm -Rf /opt/smartdc/capi/tmp
rm -Rf /opt/smartdc/capi/config
ln -s /opt/smartdc/capi-data/log /opt/smartdc/capi/log
ln -s /opt/smartdc/capi-data/tmp /opt/smartdc/capi/tmp
ln -s /opt/smartdc/capi-data/config /opt/smartdc/capi/config
# Save REVISION:
echo "${REVISION}">/opt/smartdc/capi-data/REVISION
echo "${REVISION}">/opt/smartdc/capi/REVISION
# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
echo "${APP_VERSION}">/opt/smartdc/capi-data/VERSION
echo "${APP_VERSION}">/opt/smartdc/capi/VERSION
# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/capi-repo
rm /root/capi-app-timestamp

# Adding dataset based update service for the app:
cat >"/opt/smartdc/capi-data/capi-update-service.sh" <<UPDATE
#!/usr/bin/bash

APP_NAME='capi'

APP_VERSION=\$(cat /opt/smartdc/\$APP_NAME/VERSION)
DATA_VERSION=\$(cat /opt/smartdc/\$APP_NAME-data/VERSION)

if [[ "\$APP_VERSION" != "\$DATA_VERSION" ]]; then
  echo "Calling \$APP_NAME-update"
  FROM_SMARTDC_VERSION=\$DATA_VERSION TO_SMARTDC_VERSION=\$APP_VERSION /opt/local/bin/ruby /opt/smartdc/\$APP_NAME/smartdc/update
else
  echo "\$APP_NAME is up to date"
fi

exit 0

UPDATE

chmod +x /opt/smartdc/capi-data/capi-update-service.sh
