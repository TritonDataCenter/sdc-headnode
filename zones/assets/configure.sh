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

    server {
        listen       80;
        server_name  assets;

        location / {
            root   /assets;
            index  index.html index.htm;
            autoindex on;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   share/examples/nginx/html;
        }

    }
}
NGINX
