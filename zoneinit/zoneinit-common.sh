#!/usr/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

#
# This script will become 97-zoneinit-common.sh in the zone init process, and
# will therefore be sourced before the zoneinit-finalize script.  This allows
# for some common functions to be defined.  Note that this script should _only_
# define functions and it must _not_ exit as it is sourced and not executed
# in a subshell.
#

#
# mdns_announce() will create an "announce" service to announce a particular
# application via mDNS.  It expects three arguments:  a service name, a
# port number and a type that should be used to advertise the service via
# mDNS.  (It is assumed that the service is available on the interface made
# available to the zone.)  It should be true that there exists a service with
# the following FMRI:
#
#   svc:/application/${service}:default
#
# Where ${service} is the service name converted to lower-case.
#
function mdns_announce
{
    local name=$1
    local port=$2
    local mdns=$3

    local hosts
    local ipnodes
    local zoneip
    local nsswitch="/etc/nsswitch.conf"

    local service=`echo $name | tr '[:upper:]' '[:lower:]'`
    local announcer="${service}-announcer"
    local manifest="/opt/local/share/smf/manifest/${announcer}.xml"

    #
    # Configure nsswitch to use mDNS, and enable multicast DNS:
    #
    hosts=$(grep ^hosts $nsswitch)

    if [[ ! $(echo $hosts | grep mdns) ]]; then
        $(/opt/local/bin/gsed -i"" \
            -e "s/^hosts.*$/hosts: files mdns dns/" $nsswitch)
    fi

    ipnodes=$(grep ^ipnodes $nsswitch)

    if [[ ! $(echo $ipnodes | grep mdns) ]]; then
        $(/opt/local/bin/gsed -i"" \
            -e "s/^ipnodes.*$/ipnodes: files mdns dns/" $nsswitch)
    fi

    if [[ $(svcs -Ho state dns/multicast) != "online" ]]; then
        svcadm enable -s dns/multicast
    fi

    zoneip=$(ifconfig $(zonename)0 | grep inet | awk '{print $2}')

    #
    # Create the SMF manifest -- which certainly does not make this function
    # any easier on the eyes...
    #
    cat > $manifest <<EOF
<?xml version='1.0'?>
<!DOCTYPE service_bundle SYSTEM '/usr/share/lib/xml/dtd/service_bundle.dtd.1'>
<service_bundle type='manifest' name='export'>
  <service name='site/${announcer}' type='service' version='0'>
    <create_default_instance enabled='true'/>
    <single_instance/>
    <dependency name='network' grouping='require_all' restart_on='error' type='service'>
      <service_fmri value='svc:/milestone/network:default'/>
    </dependency>
    <dependency name='filesystem' grouping='require_all' restart_on='error' type='service'>
      <service_fmri value='svc:/system/filesystem/local'/>
    </dependency>
    <dependency name='multicast' grouping='require_all' restart_on='error' type='service'>
      <service_fmri value='svc:/network/dns/multicast:default'/>
    </dependency>
    <dependency name='announcer_${service}' grouping='require_all' restart_on='restart' type='service'>
      <service_fmri value='svc:/application/${service}:default'/>
    </dependency>
    <exec_method name='start' type='method' exec='dns-sd -P Joyent ${mdns}._tcp . $port $zoneip $zoneip' timeout_seconds='60'/>
    <exec_method name='stop' type='method' exec=':kill' timeout_seconds='60'/>
    <property_group name='application' type='application'/>
    <property_group name='startd' type='framework'>
      <propval name='duration' type='astring' value='child'/>
      <propval name='ignore_error' type='astring' value='core,signal'/>
    </property_group>
    <stability value='Evolving'/>
    <template>
      <common_name>
        <loctext xml:lang='C'>$name Zeroconf Announcer (dns-sd)</loctext>
      </common_name>
    </template>
  </service>
</service_bundle>
EOF

    if  ( ! svcs -a | grep $announcer ); then
        /usr/sbin/svccfg import $manifest
        sleep 10 # XXX
        #/usr/sbin/svccfg -s svc:/site/${announcer}:default refresh
    fi

    if [[ $(svcs -Ho state $announcer) != "online" ]]; then
        if ! svcadm enable -s $announcer; then
            echo "WARNING: Failed to enable ${announcer}"
        fi
    fi
}


#
# symlink_ruby() just creates missing symlinks to ruby18 and irb18 on zones
# running ruby applications.
# It does not expect any argument.
#
function symlink_ruby
{
  # These happen to do not be created always:
  if [[ ! -e /opt/local/bin/ruby ]]; then
    echo "Symlinking ruby"
    ln -s /opt/local/bin/ruby18 /opt/local/bin/ruby
  fi

  if [[ ! -e /opt/local/bin/irb ]]; then
    echo "Symlinking irb"
    ln -s /opt/local/bin/irb18 /opt/local/bin/irb
  fi
}

#
# It's pretty obvious what create_jill_account() does. Intended to run on zones
# running ruby applications. It does not expect any arguments, for now.
#
function create_jill_account
{
  echo "Creating jill account"
  groupadd jill
  useradd -g jill -d /opt/smartdc jill
  chown -R jill:jill /opt/smartdc

  # XXX /etc/oshadow breaks changepass, not sure yet what's putting it there.
  if [[ -f /etc/oshadow ]]; then
      echo "WARNING: removing /etc/oshadow"
      rm -f /etc/oshadow
  fi

  echo "jill:naiWaic8sh" | /opt/local/sbin/changepass -n -m
  usermod -P 'Service Management' jill
  usermod -s /usr/bin/bash jill
  # Properly set PATH and other relevant stuff.
  cp /home/admin/.bash_profile /opt/smartdc/.bash_profile
  cp /home/admin/.bashrc /opt/smartdc/.bashrc
  cp /home/admin/.irbrc /opt/smartdc/.irbrc
  cp /home/admin/.profile /opt/smartdc/.profile
}

