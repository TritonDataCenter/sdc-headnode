echo "95 configuring adminui datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# adminui-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/adminui-data zones/adminui-data
# adminui-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/adminui-app-timestamp)
zfs set mountpoint=/opt/smartdc/adminui "zones/adminui-app-$STAMP"
# Get git revision:
cd /opt/smartdc/adminui-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into adminui:
cd /opt/smartdc/adminui-repo
/opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/adminui/
# Export only config into adminui-data:
cd /opt/smartdc/adminui-repo
/opt/local/bin/git checkout-index -f --prefix=/opt/smartdc/adminui-data/ config/
# Create some directories into adminui-data
mkdir -p /opt/smartdc/adminui-data/log
mkdir -p /opt/smartdc/adminui-data/tmp/pids
# Remove and symlink directories:
mv /opt/smartdc/adminui/config /opt/smartdc/adminui-data/config
rm -Rf /opt/smartdc/adminui/log
rm -Rf /opt/smartdc/adminui/tmp
rm -Rf /opt/smartdc/adminui/config
ln -s /opt/smartdc/adminui-data/log /opt/smartdc/adminui/log
ln -s /opt/smartdc/adminui-data/tmp /opt/smartdc/adminui/tmp
ln -s /opt/smartdc/adminui-data/config /opt/smartdc/adminui/config
# Save REVISION:
echo "${REVISION}">/opt/smartdc/adminui-data/REVISION
echo "${REVISION}">/opt/smartdc/adminui/REVISION
# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
echo "${APP_VERSION}">/opt/smartdc/adminui-data/VERSION
echo "${APP_VERSION}">/opt/smartdc/adminui/VERSION
# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/adminui-repo
rm /root/adminui-app-timestamp

# Adding dataset based update service for the app:
cat >"/opt/smartdc/adminui-data/adminui-update-service.sh" <<UPDATE
#!/usr/bin/bash

APP_NAME='adminui'

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

chmod +x /opt/smartdc/adminui-data/adminui-update-service.sh
