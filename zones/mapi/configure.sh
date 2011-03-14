# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/etc/configure

# Since we need to access the postgres server from other zones, we need to add configuration
echo "listen_addresses='localhost,${PRIVATE_IP}'" >> /var/pgsql/data90/postgresql.conf
echo "host    all    all    ${ADMIN_NETWORK}/${ADMIN_BITCOUNT}    password" >> /var/pgsql/data90/pg_hba.conf

# Import postgres manifest straight from the pkgsrc file:
if [[ -z $(/usr/bin/svcs -a|grep postgresql) ]]; then
  echo "Importing posgtresql service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/postgresql:pg90.xml
  /usr/sbin/svcadm enable -s postgresql
  sleep 2
else
  echo "Restarting postgresql service"
  /usr/sbin/svcadm disable -s postgresql
  /usr/sbin/svcadm enable -s postgresql
  sleep 2
fi

# We need to override nginx.conf on reconfigure, and it's safe to do during setup:
echo "Creating nginx configuration file"
cat >/opt/local/etc/nginx/nginx.conf <<NGINX
user  www  www;
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       /opt/local/etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    upstream mapi {
        server ${PRIVATE_IP}:8080;
    }

    upstream configsvc {
        server ${CA_PRIVATE_IP}:23181;
    }

    server {
        listen       ${PRIVATE_IP}:80;
        server_name  localhost;

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

        location ~ ^/ca(/.*)?$ {
            proxy_set_header  X-Real-IP  \$remote_addr;
            proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;

            proxy_pass http://configsvc;
            break;
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
  $(/opt/local/bin/gsed -i"" -e "s/^hosts.*$/hosts: files mdns dns/" /etc/nsswitch.conf)
fi

ipnodes=$(cat /etc/nsswitch.conf |grep ^ipnodes)

if [[ ! $(echo $ipnodes | grep mdns) ]]; then
  echo "Updating ipnodes entry on nsswitch.conf"
  $(/opt/local/bin/gsed -i"" -e "s/^ipnodes.*$/ipnodes: files mdns dns/" /etc/nsswitch.conf)
fi

# Do not use dns/multicast for this zone, we're using custom mDNSResponder from
# pkgsrc here:
if [[ "$(/usr/bin/svcs -Ho state dns/multicast)" == "online" ]]; then
  echo "Disabling dns/multicast"
  $(/usr/sbin/svcadm disable dns/multicast)
fi

if [[ ! $(/usr/bin/svcs -a|grep mdnsresponder) ]]; then
  echo "Importing mDNSResponder service"
  $(/usr/sbin/svccfg import /opt/local/share/smf/manifest/mdnsresponder.xml)
fi

if [[  "$(/usr/bin/svcs -Ho state mdnsresponder)" != "online"  ]]; then
  echo "Enabling mDNSResponder service."
  $(/usr/sbin/svcadm enable -s mdnsresponder)
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
  ATROPOS_ZONE_URI="${ATROPOS_PRIVATE_IP}:5984" \
  /opt/local/bin/rake18 dev:configs -f /opt/smartdc/mapi/Rakefile && \
  sleep 1 && \
  chown jill:jill /opt/smartdc/mapi/config/config.yml)

# Note these files should have been created by previous Rake task.
# If we copy these files post "gsed", everything is reset:
if [[ ! -e /opt/smartdc/mapi/config/config.ru ]]; then
  cp /opt/smartdc/mapi/config/config.ru.sample /opt/smartdc/mapi/config/config.ru
fi

if [[ ! -e /opt/smartdc/mapi/gems/gems ]] || [[ $(ls /opt/smartdc/mapi/gems/gems| wc -l) -eq 0 ]]; then
  echo "Unpacking frozen gems for MCP API."
  (cd /opt/smartdc/mapi; PATH=/opt/local/bin:$PATH /opt/local/bin/rake18 gems:deploy -f /opt/smartdc/mapi/Rakefile)
fi

if [[ ! -e /opt/smartdc/mapi/config/unicorn.smf ]]; then
  echo "Creating MCP API Unicorn Manifest."
  /opt/local/bin/ruby18 -rerb -e "user='jill';group='jill';app_environment='production';application='mcp_api'; working_directory='/opt/smartdc/mapi'; puts ERB.new(File.read('/opt/smartdc/mapi/config/deploy/unicorn.smf.erb')).result" > /opt/smartdc/mapi/config/unicorn.smf
  chown jill:jill /opt/smartdc/mapi/config/unicorn.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/unicorn.conf ]]; then
  echo "Creating MCP API Unicorn Configuration file."
  /opt/local/bin/ruby18 -rerb -e "app_port='8080'; worker_processes=1; working_directory='/opt/smartdc/mapi'; application='mcp_api'; puts ERB.new(File.read('/opt/smartdc/mapi/config/unicorn.conf.erb')).result" > /opt/smartdc/mapi/config/unicorn.conf
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

if [[ ! -e /opt/smartdc/mapi/config/heartbeater.smf ]]; then
  echo "Creating MCP API heartbeater Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:heartbeat -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/heartbeater.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/provisioner.smf ]]; then
  echo "Creating MCP API provisioner Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:provision -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/provisioner.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/dataset.smf ]]; then
  echo "Creating MCP API dataset list client Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:dataset -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/dataset.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/ur.smf ]]; then
  echo "Creating MAPI Ur Agent Client Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:ur -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/ur.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/atropos.smf ]]; then
  echo "Creating MAPI Atropos Agent Client Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:atropos -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/atropos.smf
fi

if [[ ! -e /opt/smartdc/mapi/config/zonetracker.smf ]]; then
  echo "Creating MAPI ZoneTracker Agent Client Manifest."
  RACK_ENV=production USER=jill GROUP=jill /opt/local/bin/rake18 smf:zonetracker -f /opt/smartdc/mapi/Rakefile
  chown jill:jill /opt/smartdc/mapi/config/zonetracker.smf
fi

