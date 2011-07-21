# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# Update the config with the correct values.
cat > /opt/smartdc/portal/config.js <<HERE
exports.config = {
  displayCouponField : false,
  externalUrl : "${EXTERNAL_URL}",
  publicAPIUrlV1 : "${PUBLIC_API_PRIVATE_URL}",
	publicAPIUrl : "${CLOUD_API_PRIVATE_URL}",
  publicAPIVersion : '6.1.0',
  privateCAUrl : "http://${MAPI_API_PRIVATE_IP}:80",
  privateCAPIUrl : "${CAPI_API_PRIVATE_URL}",
  CAPIuser : "${CAPI_HTTP_ADMIN_USER}",
  CAPIpassword : "${CAPI_HTTP_ADMIN_PW}",
  CAPIMetaCAKey : "portal-coal",
  CAPIMetaCABlessed : "blessed-instrumentation",
  nodemailerOpts : {
    sendmailPath : "/opt/local/sbin/sendmail",
    sender : "no-reply <no-replay@no.de>",
  },
  defaultCAParams : { module : "node", stat : "httpd_ops", decomposition : "raddr" },
  defaultCAChoices : [
    { label : "HTTP server operations", params : { module : "node", stat : "httpd_ops", decomposition : "raddr", "idle-max" : 30 }},
    { label : "HTTP client operations", params : { module : "node", stat : "httpc_ops", decomposition : "raddr", "idle-max" : 30 }},
    { label : "Socket read/write operations", params : { module : "node", stat : "socket_ops", decomposition : "raddr", "idle-max" : 30 }},
  ],
  listenIp : "${PRIVATE_IP}",
  machineListFields : [ 
			{ name: "type", heading: "Type", sortable: true, width: 104 },
      { name: "name",heading: "Machine name", sortable: true,
        mutate: function (n, machine) {
          var displayName = machine.name ||
                            machine.hostname ||
                            "Unnamed SmartMachine";
          if (displayName.length > 30) {
            displayName = displayName.substr(0, 30) + "…";
          }
          return displayName;
        },
        width: 280 },
      { name: "ips", heading: "Public IP Address", sortable: true,
      	mutate: function (n, machine) {
        	return machine.ips[0];
      	},
 			width: 140 },
      { name: "memory", heading: "RAM", sortable: true, width: 83 },
      { name: "created", date: true, heading: "Age", sortable: true, width: 130 },
      { name: "state", heading: "Status", sortable: true, width: 125 } 
    ],
	  provisionOptions :
	    [ { name: "package", alwaysShow: true, heading: "Package" },
	      { name: "dataset", alwaysShow: true, heading: "SmartMachine Type" },
	      { name: "name", heading: "Machine name" },
	      { name: "password", heading: "Machine Password" }
	    ]
}
HERE

# We need to override nginx.conf on reconfigure, and it's safe to do during setup:
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

    upstream portal {
        server ${PRIVATE_IP}:4000;
    }

    server {
        listen 80;
        rewrite ^(.*) https://\$host\$1 permanent;
    }

    server {
        listen 443;

        # Self-signed is okay. Production Zeus will handle the real no.de certs.
        ssl on;
        ssl_certificate /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_certificate_key /opt/local/etc/openssl/private/selfsigned.pem;
        ssl_prefer_server_ciphers on;

        location / {
            root /opt/smartdc/portal/public;
            proxy_set_header X-Real-IP  \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;

            ## Serve static files
            #if (-f \$request_filename) {
            #    break;
            #}

            proxy_pass http://portal;
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
nginx -C 5 -c -s 100m '/var/log/nginx/{access,error}.log'
LOGADM
