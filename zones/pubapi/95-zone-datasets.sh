echo "95 configuring pubapi datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# pubapi-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/pubapi-data zones/pubapi/data
# pubapi-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/pubapi-app-timestamp)
zfs set mountpoint=/opt/smartdc/pubapi "zones/pubapi/app-$STAMP"
# Get git revision:
cd /opt/smartdc/pubapi-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into pubapi:
cd /opt/smartdc/pubapi-repo

if [[ "${IMG_TYPE}" == "coal" ]]; then
  cp -R ./ /opt/smartdc/pubapi/
else
  /opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/pubapi/
fi

# Export only config into pubapi-data:
cd /opt/smartdc/pubapi-repo
#/opt/local/bin/git checkout-index -f --prefix=/opt/smartdc/pubapi-data/ config/
# Create some directories into pubapi-data
mkdir -p /opt/smartdc/pubapi-data/log
mkdir -p /opt/smartdc/pubapi-data/tmp/pids
# Remove and symlink directories:
mv /opt/smartdc/pubapi/config /opt/smartdc/pubapi-data/config
rm -Rf /opt/smartdc/pubapi/log
rm -Rf /opt/smartdc/pubapi/tmp
rm -Rf /opt/smartdc/pubapi/config
ln -s /opt/smartdc/pubapi-data/log /opt/smartdc/pubapi/log
ln -s /opt/smartdc/pubapi-data/tmp /opt/smartdc/pubapi/tmp
ln -s /opt/smartdc/pubapi-data/config /opt/smartdc/pubapi/config
# Save REVISION:
echo "${REVISION}">/opt/smartdc/pubapi-data/REVISION
echo "${REVISION}">/opt/smartdc/pubapi/REVISION
# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
echo "${APP_VERSION}">/opt/smartdc/pubapi-data/VERSION
echo "${APP_VERSION}">/opt/smartdc/pubapi/VERSION
# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/pubapi-repo
rm /root/pubapi-app-timestamp

# Adding dataset based update service for the app:
cat >"/opt/smartdc/pubapi-data/pubapi-update-service.sh" <<UPDATE
#!/usr/bin/bash

APP_NAME='pubapi'

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

chmod +x /opt/smartdc/pubapi-data/pubapi-update-service.sh
