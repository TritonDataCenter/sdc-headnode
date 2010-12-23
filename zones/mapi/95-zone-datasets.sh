echo "95 configuring mapi datasets"

# This needs to run after scmgit pkgsrc package has been installed:

# mapi-data dataset name will remain the same always:
zfs set mountpoint=/home/jill/mapi-data zones/mapi-data
# mapi-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/mapi-app-timestamp)
zfs set mountpoint=/home/jill/mapi "zones/mapi-app-$STAMP"
# Get git revision:
cd /home/jill/mapi-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into mapi:
cd /home/jill/mapi-repo
/opt/local/bin/git checkout-index -f -a --prefix=/home/jill/mapi/
# Export only config into mapi-data:
cd /home/jill/mapi-repo
/opt/local/bin/git checkout-index -f --prefix=/home/jill/mapi-data/ config/
# Create some directories into mapi-data
mkdir -p /home/jill/mapi-data/log
mkdir -p /home/jill/mapi-data/tmp/pids
# Remove and symlink directories:
mv /home/jill/mapi/config /home/jill/mapi-data/config
rm -Rf /home/jill/mapi/log
rm -Rf /home/jill/mapi/tmp
rm -Rf /home/jill/mapi/config
ln -s /home/jill/mapi-data/log /home/jill/mapi/log
ln -s /home/jill/mapi-data/tmp /home/jill/mapi/tmp
ln -s /home/jill/mapi-data/config /home/jill/mapi/config
# Save REVISION:
echo "${REVISION}">/home/jill/mapi-data/REVISION
echo "${REVISION}">/home/jill/mapi/REVISION
# TODO: delete mapi-repo