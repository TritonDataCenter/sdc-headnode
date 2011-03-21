# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/etc/configure

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

# CAPI specific

if [[ ! -e /opt/smartdc/capi/config/database.yml ]]; then
  su - jill -c "cd /opt/smartdc/capi; /opt/local/bin/rake18 dev:configs -f /opt/smartdc/capi/Rakefile"
fi

# Note these files should have been created by previous Rake task.
# If we copy these files post "gsed", everything is reset:
if [[ ! -e /opt/smartdc/capi/config/config.ru ]]; then
  cp /opt/smartdc/capi/config/config.ru.sample /opt/smartdc/capi/config/config.ru
fi

if [[ ! -e /opt/smartdc/capi/config/config.yml ]]; then
   cd /opt/smartdc/capi && \
   MAIL_TO="${MAIL_TO}" \
   MAIL_FROM="${MAIL_FROM}" \
   CAPI_HTTP_ADMIN_USER="${CAPI_HTTP_ADMIN_USER}" \
   CAPI_HTTP_ADMIN_PW="${CAPI_HTTP_ADMIN_PW}" \
   /opt/local/bin/rake18 install:config -f /opt/smartdc/capi/Rakefile && \
   sleep 1 && \
   chown jill:jill /opt/smartdc/capi/config/config.yml
fi

if [[ ! -e /opt/smartdc/capi/gems/gems ]] || [[ $(ls /opt/smartdc/capi/gems/gems| wc -l) -eq 0 ]]; then
  echo "Unpacking frozen gems for Customers API."
  (cd /opt/smartdc/capi; PATH=/opt/local/bin:$PATH /opt/local/bin/rake18 gems:deploy -f /opt/smartdc/capi/Rakefile)
fi

if [[ ! -e /opt/smartdc/capi/config/unicorn.smf ]]; then
  echo "Creating Customers API Unicorn Manifest."
  /opt/local/bin/ruby18 -rerb -e "user='jill';group='jill';app_environment='production';application='capi'; working_directory='/opt/smartdc/capi'; puts ERB.new(File.read('/opt/smartdc/capi/smartdc/unicorn.smf.erb')).result" > /opt/smartdc/capi/config/unicorn.smf
  chown jill:jill /opt/smartdc/capi/config/unicorn.smf
fi

if [[ ! -e /opt/smartdc/capi/config/unicorn.conf ]]; then
  echo "Creating Customers API Unicorn Configuration file."
  /opt/local/bin/ruby18 -rerb -e "app_port='8080'; worker_processes=1; working_directory='/opt/smartdc/capi'; application='capi'; puts ERB.new(File.read('/opt/smartdc/capi/smartdc/unicorn.conf.erb')).result" > /opt/smartdc/capi/config/unicorn.conf
  chown jill:jill /opt/smartdc/capi/config/unicorn.conf
fi

if [[ -z $(cat /opt/smartdc/capi/config/database.yml|grep capi) ]]; then
  echo "Configuring Customers API Database."
  cat > /opt/smartdc/capi/config/database.yml <<CAPI_DB
:development: &defaults
  :adapter: postgres
  :database: capi
  :host: $POSTGRES_HOST
  :username: $POSTGRES_USER
  :password: $POSTGRES_PW
  :encoding: UTF-8
:test:
  <<: *defaults
  :database: capi_test
:production:
  <<: *defaults
  :database: capi

CAPI_DB
fi

if [[ ! -e /opt/smartdc/capi/tmp/pids ]]; then
  su - jill -c "mkdir -p /opt/smartdc/capi/tmp/pids"
fi

# DNS API specific

if [[ ! -e /opt/smartdc/dnsapi/config/database.yml ]]; then
  echo "Creating DNS API config files."
  su - jill -c "cd /opt/smartdc/dnsapi; /opt/local/bin/rake18 dev:configs -f /opt/smartdc/dnsapi/Rakefile"
fi
sleep 1

# Note these files should have been created by previous Rake task.
# If we copy these files post "gsed", everything is reset:
if [[ ! -e /opt/smartdc/dnsapi/config/config.ru ]]; then
  cp /opt/smartdc/dnsapi/config/config.ru.sample /opt/smartdc/dnsapi/config/config.ru
fi

if [[ ! -e /opt/smartdc/dnsapi/config/config.yml ]]; then
  cp /opt/smartdc/dnsapi/config/config.yml.sample /opt/smartdc/dnsapi/config/config.yml
fi

if [[ ! -e /opt/smartdc/dnsapi/gems/gems ]] || [[ $(ls /opt/smartdc/dnsapi/gems/gems| wc -l) -eq 0 ]]; then
  echo "Unpacking frozen gems for DNS API."
  (cd /opt/smartdc/dnsapi; PATH=/opt/local/bin:$PATH /opt/local/bin/rake18 gems:deploy -f /opt/smartdc/dnsapi/Rakefile)
fi

if [[ ! -e /opt/smartdc/dnsapi/config/unicorn.smf ]]; then
  echo "Creating DNS API Unicorn Manifest."
  /opt/local/bin/ruby18 -rerb -e "user='jill';group='jill';app_environment='production';application='dnsapi'; working_directory='/opt/smartdc/dnsapi'; puts ERB.new(File.read('/opt/smartdc/dnsapi/config/deploy/unicorn.smf.erb')).result" > /opt/smartdc/dnsapi/config/unicorn.smf
  chown jill:jill /opt/smartdc/dnsapi/config/unicorn.smf
fi

if [[ ! -e /opt/smartdc/dnsapi/config/unicorn.conf ]]; then
  echo "Creating DNS API Unicorn Configuration file."
  /opt/local/bin/ruby18 -rerb -e "app_port='8000'; worker_processes=1; working_directory='/opt/smartdc/dnsapi'; application='dnsapi'; puts ERB.new(File.read('/opt/smartdc/dnsapi/config/unicorn.conf.erb')).result" > /opt/smartdc/dnsapi/config/unicorn.conf
  chown jill:jill /opt/smartdc/dnsapi/config/unicorn.conf
fi

if [[ -z $(cat /opt/smartdc/dnsapi/config/database.yml|grep dnsapi) ]]; then
  echo "Configuring DNS API Database."
  cat > /opt/smartdc/dnsapi/config/database.yml <<DNSAPI_DB

:production: &prod
  :adapter: postgres
  :database: dnsapi
  :host: $POSTGRES_HOST
  :username: $POSTGRES_USER
  :password: $POSTGRES_PW
  :encoding: UTF-8

DNSAPI_DB
fi

if [[ ! -e /opt/smartdc/dnsapi/tmp/pids ]]; then
  su - jill -c "mkdir -p /opt/smartdc/dnsapi/tmp/pids"
fi

