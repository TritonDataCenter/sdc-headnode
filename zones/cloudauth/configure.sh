# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

cat > /opt/smartdc/cloudauth/config/production.json <<HERE
{
  "capi": { 
    "url": "${CAPI_URL}",
    "username": "${CAPI_HTTP_ADMIN_USER}",
    "password": "${CAPI_HTTP_ADMIN_PW}"
  }
}
HERE
