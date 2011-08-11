# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/etc/configure

# Calculate the bitcounts
source /lib/sdc/network.sh
ADMIN_CIDR=$(ip_netmask_to_cidr ${ADMIN_NETWORK} ${ADMIN_NETMASK})
ADMIN_BITCOUNT=${ADMIN_CIDR##*/}
EXTERNAL_CIDR=$(ip_netmask_to_cidr ${EXTERNAL_NETWORK} ${EXTERNAL_NETMASK})
EXTERNAL_BITCOUNT=${EXTERNAL_CIDR##*/}

echo "listen_addresses='localhost'" >> /var/pgsql/data90/postgresql.conf

# enable slow query logging (anything beyond 200ms right now)
echo "log_min_duration_statement = 200" >> /var/pgsql/data90/postgresql.conf

# Import postgres manifest straight from the pkgsrc file:
if [[ -z $(/usr/bin/svcs -a|grep postgresql) ]]; then
  echo "Importing posgtresql service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/postgresql:pg90.xml
  sleep 10 # XXX
  #/usr/sbin/svccfg -s svc:/network/postgresql:pg90 refresh
  /usr/sbin/svcadm enable -s postgresql
else
  echo "Restarting postgresql service"
  /usr/sbin/svcadm disable -s postgresql
  /usr/sbin/svcadm enable -s postgresql
  sleep 2
fi

# We need to override nginx.conf on reconfigure, and it's safe to do during setup:
echo "Creating nginx configuration file"
cat >/opt/local/etc/nginx/nginx.conf <<NGINX
user www www;
worker_processes  1;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

events {
  worker_connections  1024;
  use /dev/poll;
}

http {
  include /opt/local/etc/nginx/mime.types;
  default_type  application/octet-stream;
  access_log /var/log/nginx/access.log;
  
  sendfile on;
  keepalive_timeout  65;

  upstream mapi {
    server 127.0.0.1:8080;
  }

  server {
    listen 80;

    location / {
      root   share/examples/nginx/html;
      index  index.html index.htm;

      proxy_set_header  X-Real-IP  \$remote_addr;
      proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header Host \$http_host;
      proxy_redirect off;

      proxy_pass http://mapi;
      break;
    }

    location /docs {
        root /opt/smartdc/mapi/public;
        index index.html;
    }

    location /ur-scripts/ {
        alias /opt/smartdc/agent-scripts/;
        autoindex on;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   share/examples/nginx/html;
    }

  }
}

NGINX

# Setup and configure nginx
if [[ -z $(/usr/bin/svcs -a|grep nginx) ]]; then
  echo "Importing nginx service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/nginx.xml
  sleep 10 # XXX
  #/usr/sbin/svccfg -s svc:/network/nginx:default refresh
  /usr/sbin/svcadm enable -s nginx
else
  echo "Restarting nginx service"
  /usr/sbin/svcadm disable -s nginx
  /usr/sbin/svcadm enable -s nginx
fi

# We don't need to reconfigure mDNS so, no need to restart services
# Configure nsswitch to use mdns & enable multicast dns:
hosts=$(cat /etc/nsswitch.conf |grep ^hosts)

if [[ ! $(echo $hosts | grep mdns) ]]; then
  echo "Updating hosts entry on nsswitch.conf"
  /opt/local/bin/gsed -i"" -e "s/^hosts.*$/hosts: files mdns dns/" /etc/nsswitch.conf
fi

ipnodes=$(cat /etc/nsswitch.conf |grep ^ipnodes)

if [[ ! $(echo $ipnodes | grep mdns) ]]; then
  echo "Updating ipnodes entry on nsswitch.conf"
  /opt/local/bin/gsed -i"" -e "s/^ipnodes.*$/ipnodes: files mdns dns/" /etc/nsswitch.conf
fi

# Do not use dns/multicast for this zone, we're using custom mDNSResponder from
# pkgsrc here:
if [[ "$(/usr/bin/svcs -Ho state dns/multicast)" == "online" ]]; then
  echo "Disabling dns/multicast"
  /usr/sbin/svcadm disable dns/multicast
fi

if [[ ! $(/usr/bin/svcs -a|grep mdnsresponder) ]]; then
  echo "Importing mDNSResponder service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/mdnsresponder.xml
  /usr/sbin/svcadm enable mdnsresponder
fi

echo "Generating MAPI config files."
host=`hostname`
amqp_user=$(echo ${RABBITMQ} | cut -d':' -f1)
amqp_pass=$(echo ${RABBITMQ} | cut -d':' -f2)
(cd /opt/smartdc/mapi && \
  SENDMAIL_TO="${MAIL_TO}" \
  SENDMAIL_FROM="${MAIL_FROM}" \
  AMQP_USER="${amqp_user}" \
  AMQP_PASSWORD="${amqp_pass}" \
  AMQP_HOST="${RABBITMQ_PRIVATE_IP}" \
  QUEUE_SYSTEM="AmqpQueueSystem" \
  EMAIL_PREFIX="[MCP API $host]" \
  MAC_PREFIX="${MAPI_MAC_PREFIX}" \
  DHCP_LEASE_TIME="${DHCP_LEASE_TIME}" \
  HTTP_ADMIN_USER="${HTTP_ADMIN_USER}" \
  HTTP_ADMIN_PW="${HTTP_ADMIN_PW}" \
 /opt/local/bin/rake dev:configs -f /opt/smartdc/mapi/Rakefile && \
  sleep 1 && \
  chown jill:jill /opt/smartdc/mapi/config/config.yml)

# Update config.ru
cp /opt/smartdc/mapi/config/config.ru.sample /opt/smartdc/mapi/config/config.ru

if [[ ! -e /opt/smartdc/mapi/gems/gems ]] || [[ $(ls /opt/smartdc/mapi/gems/gems| wc -l) -eq 0 ]]; then
  echo "Unpacking frozen gems for MCP API."
  (cd /opt/smartdc/mapi; PATH=/opt/local/bin:$PATH /opt/local/bin/rake gems:deploy -f /opt/smartdc/mapi/Rakefile)
fi

if [[ ! -e /opt/smartdc/mapi/config/unicorn.smf ]]; then
  echo "Creating MCP API Unicorn Manifest."
  /opt/local/bin/ruby -rerb -e "user='jill';group='jill';app_environment='production';application='mcp_api'; working_directory='/opt/smartdc/mapi'; puts ERB.new(File.read('/opt/smartdc/mapi/config/deploy/unicorn.smf.erb')).result" > /opt/smartdc/mapi/config/unicorn.smf
  chown jill:jill /opt/smartdc/mapi/config/unicorn.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/unicorn.conf ]]; then
  echo "Creating MCP API Unicorn Configuration file."
  /opt/local/bin/ruby -rerb -e "app_port='8080'; worker_processes=$WORKERS; working_directory='/opt/smartdc/mapi'; application='mcp_api'; puts ERB.new(File.read('/opt/smartdc/mapi/config/unicorn.conf.erb')).result" > /opt/smartdc/mapi/config/unicorn.conf
  chown jill:jill /opt/smartdc/mapi/config/unicorn.conf
fi

# It is safe to always override with the right config
echo "Configuring MCP API Database."
cat > /opt/smartdc/mapi/config/database.yml <<MAPI_DB

:production: &prod
  :adapter: postgres
  :database: mapi
  :username: $POSTGRES_USER
  :password: $POSTGRES_PW
  :host: $POSTGRES_HOST
  :encoding: UTF-8

MAPI_DB

if [[ ! -e /opt/smartdc/mapi/tmp/pids ]]; then
  su - jill -c "mkdir -p /opt/smartdc/mapi/tmp/pids"
fi

echo "Creating MCP API Heartbeater Manifest."
RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake smf:heartbeater -f /opt/smartdc/mapi/Rakefile
chown jill:jill /opt/smartdc/mapi/config/heartbeater_client.smf

echo "Creating MCP API Provisioner Manifest."
RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake smf:provisioner -f /opt/smartdc/mapi/Rakefile
chown jill:jill /opt/smartdc/mapi/config/provisioner_client.smf

echo "Creating MCP API DatasetManager client Manifest."
RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake smf:datasetmanager -f /opt/smartdc/mapi/Rakefile
chown jill:jill /opt/smartdc/mapi/config/datasetmanager_client.smf

echo "Creating MAPI Ur Client Manifest."
RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake smf:ur -f /opt/smartdc/mapi/Rakefile
chown jill:jill /opt/smartdc/mapi/config/ur_client.smf

echo "Creating MAPI ZoneTracker Client Manifest."
RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake smf:zonetracker -f /opt/smartdc/mapi/Rakefile
chown jill:jill /opt/smartdc/mapi/config/zonetracker_client.smf

# Just in case, create /var/logadm
if [[ ! -d /var/logadm ]]; then
  mkdir -p /var/logadm
fi

# Link logs to common places
mkdir -p /var/log/smartdc
ln -s /opt/smartdc/mapi/log /var/log/smartdc/mapi

# Log rotation:
cat >> /etc/logadm.conf <<LOGADM
mapi -C 10 -c -s 10m /opt/smartdc/mapi/log/*.log
nginx -C 5 -c -s 100m '/var/log/nginx/{access,error}.log'
postgresql -C 5 -c -s 100m /var/log/postgresql90.log
LOGADM

