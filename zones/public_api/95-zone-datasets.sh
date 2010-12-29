echo "95 configuring public_api datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# public_api-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/public_api-data zones/public_api-data
# public_api-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/public_api-app-timestamp)
zfs set mountpoint=/opt/smartdc/public_api "zones/public_api-app-$STAMP"
# Get git revision:
cd /opt/smartdc/public_api-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into public_api:
cd /opt/smartdc/public_api-repo
/opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/public_api/
# Export only config into public_api-data:
cd /opt/smartdc/public_api-repo
/opt/local/bin/git checkout-index -f --prefix=/opt/smartdc/public_api-data/ config/
# Create some directories into public_api-data
mkdir -p /opt/smartdc/public_api-data/log
mkdir -p /opt/smartdc/public_api-data/tmp/pids
# Remove and symlink directories:
mv /opt/smartdc/public_api/config /opt/smartdc/public_api-data/config
rm -Rf /opt/smartdc/public_api/log
rm -Rf /opt/smartdc/public_api/tmp
rm -Rf /opt/smartdc/public_api/config
ln -s /opt/smartdc/public_api-data/log /opt/smartdc/public_api/log
ln -s /opt/smartdc/public_api-data/tmp /opt/smartdc/public_api/tmp
ln -s /opt/smartdc/public_api-data/config /opt/smartdc/public_api/config
# Save REVISION:
echo "${REVISION}">/opt/smartdc/public_api-data/REVISION
echo "${REVISION}">/opt/smartdc/public_api/REVISION
# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
echo "${APP_VERSION}">/opt/smartdc/public_api-data/VERSION
echo "${APP_VERSION}">/opt/smartdc/public_api/VERSION
# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/public_api-repo
rm /root/public_api-app-timestamp

# Adding dataset based update service for the app:
cat >"/opt/smartdc/public_api-data/public_api-update-service.sh" <<UPDATE
#!/usr/bin/bash

APP_NAME='public_api'

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

chmod +x /opt/smartdc/public_api-data/public_api-update-service.sh
