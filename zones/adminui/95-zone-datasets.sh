echo "95 configuring adminui datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# adminui-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/adminui-data zones/adminui/adminui-data
# adminui-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/adminui-app-timestamp)
zfs set mountpoint=/opt/smartdc/adminui "zones/adminui/adminui-app-$STAMP"
# Get git revision:
cd /opt/smartdc/adminui-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into adminui:
cd /opt/smartdc/adminui-repo

/opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/adminui/

# Export only config into adminui-data:
cd /opt/smartdc/adminui-repo
# Create some directories into adminui-data
mkdir -p /opt/smartdc/adminui-data/log
mkdir -p /opt/smartdc/adminui-data/tmp/pids
# Remove and symlink directories:
if [[ ! -n ${KEEP_DATA_DATASET} ]]; then
  mv /opt/smartdc/adminui/config /opt/smartdc/adminui-data/config
else
  rm -Rf /opt/smartdc/adminui/config
fi
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

