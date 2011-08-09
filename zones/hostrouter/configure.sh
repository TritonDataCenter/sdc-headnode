# This script can be sourced either as part of zoneinit-finalize
# or directly from head-node global zone, when reconfiguring the zone
# for whatever the reason using /opt/smartdc/bin/configure

# Update the config with the correct values.
cat >> /opt/smartdc/hostrouter/config.js <<CONFIG
exports.riakhost = "${HOSTROUTER_RIAKHOST}"
exports.riakport = ${HOSTROUTER_RIAKPORT}
exports.riakapi = "${HOSTROUTER_RIAKAPI}"
exports.riakbucket = "hostnames"
exports.port = 80
CONFIG

mkdir /opt/riak/etc/
mkdir /opt/riak/log/

cat >> /opt/riak/etc/vm.args <<EOF
## Name of the riak node
-name riak@${PRIVATE_IP}

## Cookie for distributed erlang
-setcookie a0a6e1a375117c58d77221f10c5ce12e

## Heartbeat management; auto-restarts VM if it dies or becomes unresponsive
## (Disabled by default..use with caution!)
##-heart

## Enable kernel poll and a few async threads
+K true
+A 64

## Increase number of concurrent ports/sockets
-env ERL_MAX_PORTS 4096

## Tweak GC to run more often 
-env ERL_FULLSWEEP_AFTER 0
EOF

#FIXME: Put the cert and stuff there so that https works.
# See PAAS-269
cat >> /opt/riak/etc/app.config <<EOF
[
 %% Riak Core config
 {riak_core, [
              %% Default location of ringstate
              {ring_state_dir, "data/ring"},

              %% http is a list of IP addresses and TCP ports that the Riak
              %% HTTP interface will bind.
              {http, [ {"${PRIVATE_IP}", 8098 } ]},

              %% https is a list of IP addresses and TCP ports that the Riak
              %% HTTPS interface will bind.
              %%
              %% FIXME: It would be better to use https, but we need a
              %% cert etc.
              %{https, [{ "${PRIVATE_IP}", 8098 }]},

              %% default cert and key locations for https can be overridden
              %% with the ssl config variable
              %{ssl, [
              %       {certfile, "etc/cert.pem"},
              %       {keyfile, "etc/key.pem"}
              %      ]},
              
              %% riak_handoff_port is the TCP port that Riak uses for
              %% intra-cluster data handoff.
              {handoff_port, 8099 },
              {cluster_name, "hostrouter"},
              {ring_creation_size, 256}
             ]},

 %% Riak KV config
 {riak_kv, [
            %% Storage_backend specifies the Erlang module defining the storage
            %% mechanism that will be used on this node.
            {storage_backend, riak_kv_bitcask_backend},

            %% pb_ip is the IP address that the Riak Protocol Buffers interface
            %% will bind to.  If this is undefined, the interface will not run.
            %{pb_ip,   "0.0.0.0" },

            %% pb_port is the TCP port that the Riak Protocol Buffers interface
            %% will bind to
            %{pb_port, 8087 },

            %% raw_name is the first part of all URLS used by the Riak raw HTTP
            %% interface.  See riak_web.erl and raw_http_resource.erl for
            %% details.
            %{raw_name, "riak"},

            %% mapred_name is URL used to submit map/reduce requests to Riak.
            {mapred_name, "mapred"},

            %% directory used to store a transient queue for pending
            %% map tasks
            {mapred_queue_dir, "data/mr_queue" },

            %% Each of the following entries control how many Javascript
            %% virtual machines are available for executing map, reduce,
            %% pre- and post-commit hook functions.
            {map_js_vm_count, 8 },
            {reduce_js_vm_count, 6 },
            {hook_js_vm_count, 2 },

            %% Number of items the mapper will fetch in one request.
            %% Larger values can impact read/write performance for
            %% non-MapReduce requests.
            {mapper_batch_size, 5},

            %% js_max_vm_mem is the maximum amount of memory, in megabytes,
            %% allocated to the Javascript VMs. If unset, the default is
            %% 8MB.
            {js_max_vm_mem, 8},

            %% js_thread_stack is the maximum amount of thread stack, in megabyes,
            %% allocate to the Javascript VMs. If unset, the default is 16MB.
            %% NOTE: This is not the same as the C thread stack.
            {js_thread_stack, 16},

            %% Number of objects held in the MapReduce cache. These will be
            %% ejected when the cache runs out of room or the bucket/key
            %% pair for that entry changes
            {map_cache_size, 10000},

            %% js_source_dir should point to a directory containing Javascript
            %% source files which will be loaded by Riak when it initializes
            %% Javascript VMs.
            %{js_source_dir, "/tmp/js_source"},

            %% riak_stat enables the use of the "riak-admin status" command to
            %% retrieve information the Riak node for performance and debugging needs
            {riak_kv_stat, true}
           ]},

 %% Bitcask Config
 {bitcask, [
             {data_root, "data/bitcask"}
           ]},

 %% Luwak Config
 {luwak, [
             {enabled, false}
         ]},

%% Riak_err Config
{riak_err, [
            %% Info/error/warning reports larger than this will be considered
            %% too big to be formatted safely with the user-supplied format
            %% string.
            {term_max_size, 65536},

            %% Limit the total size of formatted info/error/warning reports.
            {fmt_max_bytes, 65536}
           ]},        

 %% SASL config
 {sasl, [
         {sasl_error_logger, {file, "log/sasl-error.log"}},
         {errlog_type, error},
         {error_logger_mf_dir, "log/sasl"},      % Log directory
         {error_logger_mf_maxbytes, 10485760},   % 10 MB max file size
         {error_logger_mf_maxfiles, 5}           % 5 files max
        ]}
].
EOF





# FIXME: Configure riak to use those values up there ^
# Update the files in /opt/riak/etc
# Right now, it's listening on 0.0.0.0, with a set-cookie
# value of "riak".  Super duper insecure and bad!


# make sure that "nobody" owns the riak folder, so that riak can run properly
chown -R nobody /opt/riak


# Setup and configure riak
if [[ -z $(/usr/bin/svcs -a|grep riak) ]]; then
  echo "Importing riak service"
  /usr/sbin/svccfg import /opt/smartdc/hostrouter/riak-service.xml
  sleep 10 # XXX
  #/usr/sbin/svccfg -s svc:/application/riak:default refresh
  /usr/sbin/svcadm enable -s riak
else
  echo "Restarting riak service"
  /usr/sbin/svcadm disable -s riak
  /usr/sbin/svcadm enable -s riak
fi
