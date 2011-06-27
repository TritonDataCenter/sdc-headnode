# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/etc/configure

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

    upstream adminui {
        server ${PRIVATE_IP}:8080;
    }

    upstream caproxy {
        server ${PRIVATE_IP}:8081;
    }

    server {
        listen 80;
        rewrite ^(.*) https://\$server_addr\$request_uri permanent;
    }

    server {
        listen       443    ssl;
        server_name  adminui;
        ssl on;
        ssl_certificate /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_certificate_key /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_prefer_server_ciphers on;

        location / {
            root   share/examples/nginx/html;
            index  index.html index.htm;

            proxy_set_header  X-Real-IP  \$remote_addr;
            proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;

            proxy_pass http://adminui;
            break;
        }

        location /ca {
            root   share/examples/nginx/html;
            index  index.html index.htm;

            proxy_set_header  X-Real-IP  \$remote_addr;
            proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;

            proxy_pass http://caproxy;
            break;
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

# Note these files should have been created by previous Rake task.
# If we copy these files post "gsed", everything is reset:
if [[ ! -e /opt/smartdc/adminui/config/config.ru ]]; then
  cp /opt/smartdc/adminui/config/config.ru.sample /opt/smartdc/adminui/config/config.ru
fi

if [[ ! -e /opt/smartdc/adminui/gems/gems ]] || [[ $(ls /opt/smartdc/adminui/gems/gems| wc -l) -eq 0 ]]; then
  echo "[ADMINUI] Unpacking frozen gems"
  (cd /opt/smartdc/adminui; PATH=/opt/local/bin:$PATH /opt/local/bin/rake gems:deploy -f /opt/smartdc/adminui/Rakefile)
fi

if [[ ! -e /opt/smartdc/adminui/config/unicorn.smf ]]; then
  echo "[ADMINUI] Creating Unicorn Manifest."
  /opt/local/bin/ruby -rerb -e "user='jill';group='jill';app_environment='production';application='adminui'; working_directory='/opt/smartdc/adminui'; puts ERB.new(File.read('/opt/smartdc/adminui/config/deploy/unicorn.smf.erb')).result" > /opt/smartdc/adminui/config/unicorn.smf
  chown jill:jill /opt/smartdc/adminui/config/unicorn.smf
fi

if [[ ! -e /opt/smartdc/adminui/config/unicorn.conf ]]; then
  echo "[ADMINUI] Creating Unicorn Configuration file."
  /opt/local/bin/ruby -rerb -e "app_port='8080'; worker_processes=$WORKERS; working_directory='/opt/smartdc/adminui'; application='adminui'; puts ERB.new(File.read('/opt/smartdc/adminui/config/unicorn.conf.erb')).result" > /opt/smartdc/adminui/config/unicorn.conf
  chown jill:jill /opt/smartdc/adminui/config/unicorn.conf
fi

echo "[ADMINUI] Generating config.json"
host=`hostname`

su - jill -c "cd /opt/smartdc/adminui; \
  DATACENTER_NAME=$DATACENTER_NAME \
  ADMINUI_IP=$ADMINUI_IP \
  MAIL_FROM=$MAIL_FROM \
  MAIL_TO=$MAIL_TO \
  DSAPI_URL=$DSAPI_URL \
  DSAPI_USER=$DSAPI_USER \
  DSAPI_PASS=$DSAPI_PASS \
  CAPI_URL=$CAPI_URL \
  CAPI_HTTP_ADMIN_USER=$CAPI_HTTP_ADMIN_USER \
  CAPI_HTTP_ADMIN_PW=$CAPI_HTTP_ADMIN_PW \
  MAPI_URL=$MAPI_URL \
  MAPI_HTTP_ADMIN_USER=$MAPI_HTTP_ADMIN_USER \
  MAPI_HTTP_ADMIN_PW=$MAPI_HTTP_ADMIN_PW \
  HVM=$HAVE_HVM \
  /opt/local/bin/rake config -f /opt/smartdc/adminui/Rakefile"

if [[ ! -e /opt/smartdc/adminui/tmp/pids ]]; then
  su - jill -c "mkdir -p /opt/smartdc/adminui/tmp/pids"
fi

# Just in case, create /var/logadm
if [[ ! -d /var/logadm ]]; then
  mkdir -p /var/logadm
fi

# Log rotation:
cat >> /etc/logadm.conf <<LOGADM
adminui -C 10 -c -s 100m /opt/smartdc/adminui/log/*.log
nginx -C 5 -c -s 100m '/var/log/nginx/{access,error}.log'
LOGADM
