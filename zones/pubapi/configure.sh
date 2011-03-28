# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/etc/configure

cat >"/opt/smartdc/pubapi/config/config.yml" <<CONFIGYML
---
development: &defaults
  name: Joyent Public API
  url: http://${PUBLIC_IP}:8080/v1
  ignore_coupons: true
  datastore:
    adapter: sqlite3
    path: development.db
  sendmail:
    sendmail_path: /opt/local/sbin/sendmail
    sendmail_arguments: '-i -t'
    to: ${MAIL_TO}
    from: ${MAIL_FROM}
  capi:
    url: ${CAPI_URL}
    username: ${CAPI_HTTP_ADMIN_USER}
    password: ${CAPI_HTTP_ADMIN_PW}
    cache_size: ${CAPI_CACHE_SIZE}
    cache_age: ${CAPI_CACHE_AGE}
  mapi:
    ${DEFAULT_DATACENTER}:
      url: ${MAPI_URL}
      username: ${MAPI_HTTP_ADMIN_USER}
      password: ${MAPI_HTTP_ADMIN_PW}
      resources:
        smartos:
          default_limit: ${SMARTOS_DEFAULT_LIMIT}
          coupon: false
          repo: false
        nodejs:
          default_limit: ${NODEJS_DEFAULT_LIMIT}
          coupon: false
          repo: true
          ram: 128

staging:
  <<: *defaults

test:
  <<: *defaults

production:
  datastore:
    adapter: sqlite3
    path: db/production.db
  <<: *defaults
CONFIGYML

echo "Creating nginx configuration file"
cat >/opt/local/etc/nginx/nginx.conf <<NGINX
user www www;
worker_processes 1;
error_log /var/log/nginx/error.log;
#pid /var/spool/nginx/nginx.pid;

events {
    worker_connections 1024;
    use /dev/poll; # important on Solaris
}

http {
    include /opt/local/etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '\$remote_addr - \$remote_user [\$time_local] \$request '
                    '"\$status" \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    sendfile off; # important on Solaris
    keepalive_timeout 60;
    server_tokens off;

    upstream pubapi {
        server ${PRIVATE_IP}:8080;
    }

    server {
        listen 443;

        # Self-signed is okay. Production Zeus will handle the real no.de certs.
        ssl on;
        ssl_certificate /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_certificate_key /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_prefer_server_ciphers on;

        location / {
            root /opt/smartdc/pubapi/public;
            proxy_set_header X-Real-IP  \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;

            ## Serve static files
            #if (-f \$request_filename) {
            #    break;
            #}

            proxy_pass http://pubapi;
            break;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root share/examples/nginx/html;
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

# Just in case, create /var/logadm
if [[ ! -d /var/logadm ]]; then
  mkdir -p /var/logadm
fi

# Log rotation:
cat >> /etc/logadm.conf <<LOGADM
pubapi -C 10 -c -s 100m /opt/smartdc/pubapi/log/*.log
nginx -C 5 -c -s 100m '/var/log/nginx/{access,error}.log'
LOGADM
