echo "95 configuring mapi datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# mapi-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/mapi-data zones/mapi/mapi-data
# mapi-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/mapi-app-timestamp)
zfs set mountpoint=/opt/smartdc/mapi "zones/mapi/mapi-app-$STAMP"
# Get git revision:
cd /opt/smartdc/mapi-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into mapi:
cd /opt/smartdc/mapi-repo

/opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/mapi/

# Export only config into mapi-data:
cd /opt/smartdc/mapi-repo
# Create some directories into mapi-data
mkdir -p /opt/smartdc/mapi-data/log
mkdir -p /opt/smartdc/mapi-data/tmp/pids
# Remove and symlink directories:
mv /opt/smartdc/mapi/config /opt/smartdc/mapi-data/config
rm -Rf /opt/smartdc/mapi/log
rm -Rf /opt/smartdc/mapi/tmp
rm -Rf /opt/smartdc/mapi/config
ln -s /opt/smartdc/mapi-data/log /opt/smartdc/mapi/log
ln -s /opt/smartdc/mapi-data/tmp /opt/smartdc/mapi/tmp
ln -s /opt/smartdc/mapi-data/config /opt/smartdc/mapi/config
# Save REVISION:
echo "${REVISION}">/opt/smartdc/mapi-data/REVISION
echo "${REVISION}">/opt/smartdc/mapi/REVISION
# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
echo "${APP_VERSION}">/opt/smartdc/mapi-data/VERSION
echo "${APP_VERSION}">/opt/smartdc/mapi/VERSION
# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/mapi-repo
rm /root/mapi-app-timestamp

# Adding dataset based update service for the app:
cat >"/opt/smartdc/mapi-data/mapi-update-service.sh" <<UPDATE
#!/usr/bin/bash

APP_NAME='mapi'

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

chmod +x /opt/smartdc/mapi-data/mapi-update-service.sh
