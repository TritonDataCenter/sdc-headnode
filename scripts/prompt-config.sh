#!/usr/bin/bash

# XXX - TODO
# - if $ntp_hosts == "local", configure ntp for no external time source
# - try to figure out why ^C doesn't intr when running under SMF

PATH=/usr/sbin:/usr/bin
export PATH

# Defaults
datacenter_headnode_id=0
mail_to="root@localhost"
ntp_hosts="pool.ntp.org"
dns_resolver1="8.8.8.8"
dns_resolver2="8.8.4.4"

# Globals
declare -a states
declare -a nics
declare -a assigned

sigexit()
{
	echo
	echo "Headnode system configuration has not been completed."
	echo "You must reboot to re-run system configuration."
	exit 0
}

#
# Get the max. IP addr for the given field, based in the netmask.
# That is, if netmask is 255, then its just the input field, otherwise its
# the host portion of the netmask (e.g. netmask 224 -> 31).
# Param 1 is the field and param 2 the mask for that field.
#
max_fld()
{
	comp=$((255 & ~$2))
	fmax=$(($comp | $1))
}

#
# Converts an IP and netmask to a network
# For example: 10.99.99.7 + 255.255.255.0 -> 10.99.99.0
# Each field is in the net_a, net_b, net_c and net_d variables.
# Also, host_addr stores the address of the host w/o the network number (e.g.
# 7 in the 10.99.99.7 example above).  Also, max_host stores the max. host
# number (e.g. 10.99.99.254 in the example above).
#
ip_netmask_to_network()
{
	IP=$1
	NETMASK=$2

	OLDIFS=$IFS
	IFS=.
	set -- $IP
	net_a=$1
	net_b=$2
	net_c=$3
	net_d=$4
	addr_d=$net_d

	set -- $NETMASK

	# Calculate the maximum host address
	max_fld "$net_a" "$1"
	max_a=$fmax
	max_fld "$net_b" "$2"
	max_b=$fmax
	max_fld "$net_c" "$3"
	max_c=$fmax
	max_fld "$net_d" "$4"
	max_d=$(expr $fmax - 1)
	max_host="$max_a.$max_b.$max_c.$max_d"

	net_a=$(($net_a & $1))
	net_b=$(($net_b & $2))
	net_c=$(($net_c & $3))
	net_d=$(($net_d & $4))

	host_addr=$(($addr_d & ~$4))
	IFS=$OLDIFS
}

# Sets two variables, use_lo and use_hi, which are the usable IP addrs for the
# largest block of available host addresses on the subnet, based on the two
# addrs the user has chosen for the GW and External Host IP.
# We look at the three ranges (upper, middle, lower) defined by the two addrs.
calc_ext_default_range()
{
	a1=$1
	a2=$2

	if [ $a1 -lt $a2 ]; then
		lo=$a1
		hi=$a2
	else
		lo=$a2
		hi=$a1
	fi

	u_start=`expr $hi + 1`
	m_start=`expr $lo + 1`
	l_start=1

	u_max=$max_d
	m_max=`expr $hi - 1`
	l_max=`expr $lo - 1`

	up_range=`expr $max_d - $hi`
	mid_range=`expr $hi - $lo`
	lo_range=`expr $lo - 2`
	[ $lo_range -lt 1 ] && lo_range=0

	if [ $up_range -gt $mid_range ]; then
		use_lo=$u_start
		use_hi=$u_max
		range=$up_range
	else
		use_lo=$m_start
		use_hi=$m_max
		range=$mid_range
	fi

	if [ $range -lt $lo_range ]; then
		use_lo=$l_start
		use_hi=$l_max
	fi
}

# Tests whether entire string is a number.
isdigit ()
{
	[ $# -eq 1 ] || return 1

	case $1 in
  	*[!0-9]*|"") return 1;;
	*) return 0;;
	esac
}

# Tests network numner (num.num.num.num)
is_net()
{
	NET=$1

	OLDIFS=$IFS
	IFS=.
	set -- $NET
	a=$1
	b=$2
	c=$3
	d=$4
	IFS=$OLDIFS

	isdigit "$a" || return 1
	isdigit "$b" || return 1
	isdigit "$c" || return 1
	isdigit "$d" || return 1

	[ -z $a ] && return 1
	[ -z $b ] && return 1
	[ -z $c ] && return 1
	[ -z $d ] && return 1

	[ $a -lt 0 ] && return 1
	[ $a -gt 255 ] && return 1
	[ $b -lt 0 ] && return 1
	[ $b -gt 255 ] && return 1
	[ $c -lt 0 ] && return 1
	[ $c -gt 255 ] && return 1
	[ $d -lt 0 ] && return 1
	# Make sure the last field isn't the broadcast addr.
	[ $d -ge 255 ] && return 1
	return 0
}

# Tests if input is an email address
is_email() {
  regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.?)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
  ADDRESS=$1
  
  [[ $ADDRESS =~ $regex ]] && return 0
	return 1
}

# Optional input
promptopt()
{
	val=""
	def="$2"
	if [ -z "$def" ]; then
		printf "%s [press enter for none]: " "$1"
	else
		printf "%s [%s]: " "$1" "$def"
	fi
	read val
	# If def was null and they hit return, we just assign null to val
	[ -z "$val" ] && val="$def"
}

promptval()
{
	val=""
	def="$2"
	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			printf "%s [%s]: " "$1" "$def"
		else
			printf "%s: " "$1"
		fi
		read val
		[ -z "$val" ] && val="$def"
		[ -n "$val" ] && break
		echo "A value must be provided."
	done
}

promptemail()
{
	val=""
	def="$2"
	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			printf "%s [%s]: " "$1" "$def"
		else
			printf "%s: " "$1"
		fi
		read val
		[ -z "$val" ] && val="$def"
		is_email "$val" || val=""
		[ -n "$val" ] && break
		echo "A valid email address must be provided."
	done
}

# Input must be a valid network number (see is_net())
promptnet()
{
	val=""
	def="$2"
	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			printf "%s [%s]: " "$1" "$def"
		else
			printf "%s: " "$1"
		fi
		read val
		[ -z "$val" ] && val="$def"
		is_net "$val" || val=""
		[ -n "$val" ] && break
		echo "A valid network number (n.n.n.n) must be provided."
	done
}

printnics()
{
	i=1
	printf "%-6s %-9s %-18s %-7s %-10s\n" "Number" "Link" "MAC Address" \
	    "State" "Network"
	while [ $i -le $nic_cnt ]; do
		printf "%-6d %-9s %-18s %-7s %-10s\n" $i ${nics[$i]} \
		    ${macs[$i]} ${states[$i]} ${assigned[i]}
		((i++))
	done
}

# Must choose a valid NIC on this system
promptnic()
{
	if [[ $nic_cnt -eq 1 ]]; then
		val="${macs[1]}"
		return
	fi

	printnics
	num=0
	while [ /usr/bin/true ]; do
		printf "Enter the number of the NIC for the %s interface: " \
		   "$1"
		read num
		if ! [[ "$num" =~ ^[0-9]+$ ]] ; then
			echo ""
		elif [ $num -ge 1 -a $num -le $nic_cnt ]; then
			mac_addr="${macs[$num]}"
			assigned[$num]=$1
			break
		fi
		# echo "You must choose between 1 and $nic_cnt."
		updatenicstates
		printnics
	done

	val=$mac_addr
}

promptpw()
{
	def="$3"

	while [ /usr/bin/true ]; do
		val=""
		while [ -z "$val" ]; do
			if [ -z "$def" ]; then
				printf "%s: " "$1"
			else
				printf "%s [enter to keep existing]: " "$1"
			fi

			stty -echo
			read val
			stty echo
			echo
			if [ -n "$val" ]; then
				if [ "$2" == "chklen" -a ${#val} -lt 6 ]; then
					echo "The password must be at least" \
					    "6 characters long."
					val=""
				else
	 				break
				fi
			else 
				if [ -n "$def" ]; then
					val=$def
	 				return
				else
					echo "A value must be provided."
				fi
			fi
		done

		cval=""
		while [ -z "$cval" ]; do
			printf "%s: " "Confirm password"
			stty -echo
			read cval
			stty echo
			echo
			[ -n "$cval" ] && break
			echo "A value must be provided."
		done

		[ "$val" == "$cval" ] && break

		echo "The entries do not match, please re-enter."
	done
}

updatenicstates()
{
	states=(1)
	#states[0]=1
	while IFS=: read -r link state ; do
		states=( ${states[@]-} $(echo "$state") )
	done < <(dladm show-phys -po link,state 2>/dev/null)
}

printheader() 
{
  local newline=
  local cols=`tput cols`
  local subheader=$1
  
  if [ $cols -gt 80 ] ;then
    newline='\n'
  fi
  
  clear
  printf " %-40s\n" "Smart Data Center (SDC) Setup"
  printf " %-40s%38s\n" "$subheader" "http://wiki.joyent.com/sdcinstall"
  for i in {1..80} ; do printf "-" ; done && printf "$newline"

}

trap sigexit SIGINT

USBMNT=$1

#
# Get local NIC info
#
nic_cnt=0

while IFS=: read -r link addr ; do
    ((nic_cnt++))
    nics[$nic_cnt]=$link
    macs[$nic_cnt]=`echo $addr | sed 's/\\\:/:/g'`
    assigned[$nic_cnt]="-"
done < <(dladm show-phys -pmo link,address 2>/dev/null)

if [[ $nic_cnt -lt 1 ]]; then
	echo "ERROR: cannot configure the system, no NICs were found."
	exit 0
fi

ifconfig -a plumb
updatenicstates

export TERM=sun-color
export TERM=xterm-color
stty erase ^H

printheader "Copyright 2011, Joyent, Inc."

message="
You must answer the following questions to configure the headnode.
You will have a chance to review and correct your answers, as well as a
chance to edit the final configuration, before it is applied.

Press [enter] to continue"

printf "$message"
read continue;

if [ -f /tmp/config_in_progress ]; then
	message="
Configuration is already in progress on another terminal.
This session can no longer perform system configuration.\n"
	while [ /usr/bin/true ]; do
		printf "$message"
		read continue;
	done

fi
touch /tmp/config_in_progress

#
# Main loop to prompt for user input
#
while [ /usr/bin/true ]; do

	printheader "Datacenter Information"
	message="
The following questions will be used to configure your headnode identity. 
This identity information is used to uniquely identify your headnode as well
as help with management of distributed systems. If you are setting up a second 
headnode at a datacenter, then please have the ID of the previous headnode 
handy.\n\n"

	printf "$message"

	promptval "Enter the company name" "$datacenter_company_name"
	datacenter_company_name="$val"

	promptval "Enter a name for this datacenter" "$datacenter_name"
	datacenter_name="$val"

	promptval "Enter the City and State for this datacenter" \
	    "$datacenter_location"
	datacenter_location="$val"

	promptval "Enter your headnode ID or press enter to accept the default"\
	    "$datacenter_headnode_id"
	datacenter_headnode_id="$val"

	printheader "Networking" 
	message="
Several applications will be made available on these networks using IP 
addresses which are automatically incremented based on the headnode IP. 
In order to determine what IP addresses have been assigned to SDC, you can
either review the configuration prior to its application, or you can run 
'sdc-netinfo' after the install.

Press [enter] to continue"

	printf "$message"
	read continue

	printheader "Networking - Admin"
	message="
The admin network is used for management traffic and other information that
flows between the Compute Nodes and the Headnode in an SDC cluster. This
network will be used to automatically provision new compute nodes and there are
several application zones which are assigned sequential IP addresses on this
network. It is important that this network be used exclusively for SDC
management. Note that DHCP traffic will be present on this network following
the installation and that this network is connected in VLAN ACCESS mode only.\n\n"
  
	printf "$message"
	
	promptnic "'admin'"
	admin_nic="$val"

	promptnet "(admin) headnode IP address" "$admin_ip"
	admin_ip="$val"

	[[ -z "$admin_netmask" ]] && admin_netmask="255.255.255.0"

	promptnet "(admin) headnode netmask" "$admin_netmask"
	admin_netmask="$val"

	promptnet "(admin) gateway IP address" "$admin_gateway"
	admin_gateway="$val"

	if [[ -z "$admin_zone_ip" ]]; then
		ip_netmask_to_network "$admin_ip" "$admin_netmask"
		next_addr=$(expr $host_addr + 1)
		admin_zone_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
	fi

	promptnet "(admin) Zone's starting IP address" "$admin_zone_ip"
	admin_zone_ip="$val"

	printheader "Networking - External"
	message="
The external network is used by the headnode and its applications to connect to
external networks. That is, it can be used to communicate with either the
Internet, an intranet, or any other WAN.  There are four application zones
visible on the external network which will need assigned addresses.\n\n"
  
	printf "$message"

	promptnic "'external'"
	external_nic="$val"

	promptnet "(external) headnode IP address" "$external_ip"
	external_ip="$val"

	[[ -z "$external_netmask" ]] && external_netmask="255.255.255.0"

	promptnet "(external) headnode netmask" "$external_netmask"
	external_netmask="$val"

	promptnet "(external) gateway IP address" "$external_gateway"
	external_gateway="$val"

	promptopt "(external) VLAN ID" "$external_vlan_id"
	external_vlan_id="$val"

	if [[ -z "$external_provisionable_start" ]]; then
		# Initialize the external IP defaults for adminui, capi,
		# cloudapi and portal.  By default we'll use the range .3 - .6
		# but we need to check for collisions on the external IP
		# and gateway.

		ip_netmask_to_network "$external_gateway" "$external_netmask"
		gw_host_addr=$host_addr

		ip_netmask_to_network "$external_ip" "$external_netmask"

		# Get use_lo and use_hi values for defaults
		calc_ext_default_range $gw_host_addr $host_addr

		gw_host_addr=$(expr $net_d + $gw_host_addr)

		# host_addr is the number of IPs above the subnet's start
		# address, so convert these addresses to real (not relative)
		# IPs:
		next_addr=$(expr $net_d + $use_lo)
		adminui_external_ip="$net_a.$net_b.$net_c.$next_addr"
		next_addr=$(expr $next_addr + 1)
		billapi_external_ip="$net_a.$net_b.$net_c.$next_addr"
		next_addr=$(expr $next_addr + 1)
		capi_external_ip="$net_a.$net_b.$net_c.$next_addr"
		next_addr=$(expr $next_addr + 1)
		cloudapi_external_ip="$net_a.$net_b.$net_c.$next_addr"
		next_addr=$(expr $next_addr + 1)
		portal_external_ip="$net_a.$net_b.$net_c.$next_addr"

		# By default, start the provisionable range 5 addrs after the
		# external IPs for the zones above.
		next_addr=$(expr $next_addr + 5)
		external_provisionable_start="$net_a.$net_b.$net_c.$next_addr"

		external_provisionable_end="$max_a.$max_b.$max_c.$use_hi"
	fi

	promptnet " AdminUI zone external IP address" "$adminui_external_ip"
	adminui_external_ip="$val"

	promptnet " BillAPI zone external IP address" "$billapi_external_ip"
	billapi_external_ip="$val"

	promptnet "    CAPI zone external IP address" "$capi_external_ip"
	capi_external_ip="$val"

	promptnet "CloudAPI zone external IP address" "$cloudapi_external_ip"
	cloudapi_external_ip="$val"

	promptnet "  Portal zone external IP address" "$portal_external_ip"
	portal_external_ip="$val"

	promptnet "Starting provisionable IP address" \
	   "$external_provisionable_start"
	external_provisionable_start="$val"

	promptnet "  Ending provisionable IP address" \
	   "$external_provisionable_end"
	external_provisionable_end="$val"

	printheader "Networking - Continued"
	message=""
  
	printf "$message"

	message="
The default gateway will determine which router will be used to connect to
other networks. This will almost certainly be the router connected to your
'External' network.\n\n"

	printf "$message"

	[[ -z "$headnode_default_gateway" ]] && \
	    headnode_default_gateway="$external_gateway"

	promptnet "Enter the default gateway IP" "$headnode_default_gateway"
	headnode_default_gateway="$val"

	message="
\nThe DNS servers set here will be used to provide name resolution abilities to
the SDC cluster itself. These will also be default DNS servers for zones
provisioned on the 'external' network.\n\n"

	printf "$message"

	promptval "Enter the Primary DNS server IP" "$dns_resolver1"
	dns_resolver1="$val"
	promptval "Enter the Secondary DNS server IP" "$dns_resolver2"
	dns_resolver2="$val"
	promptval "Enter the headnode domain name" "$domainname"
	domainname="$val"
	promptval "Default DNS search domain" "$dns_domain"
	dns_domain="$val"
	
	message="
\nBy default the headnode acts as an NTP server for the admin network. You can
set the headnode to be an NTP client to synchronize to another NTP server.\n"

	printf "$message"

	promptval "Enter an NTP server IP address or hostname" "$ntp_hosts"
	ntp_hosts="$val"

 
	printheader "Account Information"
	message="
There are two primary accounts for managing a Smart Data Center.  These are
'admin', and 'root'. Each user can have a unique password. Most of the
interaction you will have with SDC will be using the 'admin' user, unless
otherwise specified.  There is also an internal HTTP API password used by
various services to communicate with each other.  In addition, SDC has the
ability to send notification emails to a specific address. Each of these
values will be configured below.\n\n"

	printf "$message"
	
	promptpw "Enter root password" "nolen" "$root_shadow"
	root_shadow="$val"
	
	promptpw "Enter admin password" "chklen" "$zone_admin_pw"
	zone_admin_pw="$val"
	
	promptpw "Enter HTTP API svc password" "chklen" "$http_admin_pw"
	http_admin_pw="$val"
	
	promptemail "Administrator email goes to" "$mail_to"
	mail_to="$val"

	[[ -z "$mail_from" ]] && mail_from="support@${domainname}"
	promptemail "Support email should appear from" "$mail_from"
	mail_from="$val"

	printheader "Verify Configuration"
	message=""
  
	printf "$message"

	printf "Company name: $datacenter_company_name\n"
	printf "Datacenter Name: %s, Location: %s\n" \
	    "$datacenter_name" "$datacenter_location"
	printf "Headnode ID: $datacenter_headnode_id\n"
	printf "Email Admin Address: %s, From: %s\n" \
	    "$mail_to" "$mail_from"
	printf "Domain name: %s, Gateway IP address: %s\n" \
	    $domainname $headnode_default_gateway
	if [ -z "$external_vlan_id" ]; then
		ext_vlanid="none"
	else
		ext_vlanid="$external_vlan_id"
	fi
	printf "%8s %17s %15s %15s %15s %4s\n" "Net" "MAC" \
	    "IP addr." "Netmask" "Gateway" "VLAN"
	printf "%8s %17s %15s %15s %15s %4s\n" "Admin" $admin_nic \
	    $admin_ip $admin_netmask $admin_gateway "none"
	printf "%8s %17s %15s %15s %15s %4s\n" "External" $external_nic \
	    $external_ip $external_netmask $external_gateway $ext_vlanid
	echo
	printf "%15s %15s %15s %15s %15s\n" \
	    "AdminUI" "BillAPI" "CAPI" "CloudAPI" "Portal"
	printf "%15s %15s %15s %15s %15s\n" \
	    "$adminui_external_ip" "$billapi_external_ip" "$capi_external_ip" \
	    "$cloudapi_external_ip" "$portal_external_ip"
	printf "Admin net zone IP addresses start at: %s\n" $admin_zone_ip
	printf "Provisionable IP range: %s - %s\n" \
	    $external_provisionable_start $external_provisionable_end
	printf "DNS Servers: (%s, %s), Search Domain: %s\n" \
	    "$dns_resolver1" "$dns_resolver2" "$dns_domain"
	printf "NTP server: $ntp_hosts\n"
	echo

	promptval "Is this correct?" "y"
	[ "$val" == "y" ] && break
	clear
done

#
# Calculate admin and external network
#
ip_netmask_to_network "$admin_ip" "$admin_netmask"
admin_network="$net_a.$net_b.$net_c.$net_d"

#
# Calculate admin network IP address for each zone
#
ip_netmask_to_network "$admin_zone_ip" "$admin_netmask"
next_addr=$host_addr
adminui_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

next_addr=$(expr $next_addr + 1)
assets_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

next_addr=$(expr $next_addr + 1)
ca_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
ca_client_url="http://${ca_admin_ip}:23181"

next_addr=$(expr $next_addr + 1)
capi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
capi_client_url="http://${capi_admin_ip}:8080"
capi_external_url="http://${capi_external_ip}:8080"

next_addr=$(expr $next_addr + 1)
dhcpd_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

next_addr=$(expr $next_addr + 1)
mapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
mapi_client_url="http://${mapi_admin_ip}:80"

# Portal zone is NOT on the admin net
# next_addr=$(expr $next_addr + 1)
# portal_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
portal_external_url="https://${portal_external_ip}"

next_addr=$(expr $next_addr + 1)
cloudapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
cloudapi_external_url="https://${cloudapi_external_ip}"

next_addr=$(expr $next_addr + 1)
rabbitmq_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
rabbitmq="guest:guest:${rabbitmq_admin_ip}:5672"

next_addr=$(expr $next_addr + 1)
billapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
billapi_external_url="http://${billapi_external_ip}"

next_addr=$(expr $next_addr + 1)
riak_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

next_addr=$(expr $next_addr + 1)
dhcp_next_server="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"

# Add 5 to leave some room
next_addr=$(expr $next_addr + 5)
dhcp_range_start="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
dhcp_range_end="$max_host"

#
# Calculate external network
#
ip_netmask_to_network "$external_ip" "$external_netmask"
external_network="$net_a.$net_b.$net_c.$net_d"

#
# Generate config file
#
tmp_config=$USBMNT/tmp_config

echo "#" >$tmp_config
echo "# This file was auto-generated and must be source-able by bash." \
    >>$tmp_config
echo "#" >>$tmp_config
echo >>$tmp_config

# If in a VM, setup coal so networking will work.
platform=$(smbios -t1 | nawk '{if ($1 == "Product:") print $2}')
[ "$platform" == "VMware" ] && echo "coal=true" >>$tmp_config

echo "swap=0.25x" >>$tmp_config
echo "compute_node_swap=0.25x" >>$tmp_config
echo >>$tmp_config

echo "# datacenter_name should be unique among your cloud," >>$tmp_config
echo "# datacenter_headnode_id should be a positive integer that is unique" \
     >>$tmp_config
echo "# for this headnode within that datacenter" >>$tmp_config
echo "datacenter_name=$datacenter_name" >>$tmp_config
echo "datacenter_company_name=\"$datacenter_company_name\"" >>$tmp_config
echo "datacenter_location=\"$datacenter_location\"" >>$tmp_config
echo "datacenter_headnode_id=$datacenter_headnode_id" >>$tmp_config
echo >>$tmp_config

echo "default_rack_name=RACK1" >>$tmp_config
echo "default_rack_size=30" >>$tmp_config
echo "default_server_role=pro" >>$tmp_config
echo "default_package_sizes=\"128,256,512,1024\"" >>$tmp_config
echo >>$tmp_config

echo "# These settings are used by all services in your cloud for email messages" \
    >>$tmp_config
echo "mail_to=$mail_to" >>$tmp_config
echo "mail_from=$mail_from" >>$tmp_config
echo >>$tmp_config

echo "# admin_nic is the nic admin_ip will be connected to for headnode zones."\
    >>$tmp_config
echo "admin_nic=$admin_nic" >>$tmp_config
echo "admin_ip=$admin_ip" >>$tmp_config
echo "admin_netmask=$admin_netmask" >>$tmp_config
echo "admin_network=$admin_network" >>$tmp_config
echo "admin_gateway=$admin_gateway" >>$tmp_config
echo >>$tmp_config

echo "# external_nic is the nic external_ip will be connected to for headnode zones." \
    >>$tmp_config
echo "external_nic=$external_nic" >>$tmp_config
echo "external_ip=$external_ip" >>$tmp_config
echo "external_gateway=$external_gateway" >>$tmp_config
echo "external_netmask=$external_netmask" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# external_vlan_id=999" >>$tmp_config
else
	echo "external_vlan_id=$external_vlan_id" >>$tmp_config
fi
echo "external_network=$external_network" >>$tmp_config
echo "external_provisionable_start=$external_provisionable_start" >>$tmp_config
echo "external_provisionable_end=$external_provisionable_end" >>$tmp_config
echo >>$tmp_config

echo "headnode_default_gateway=$headnode_default_gateway" >>$tmp_config
echo "compute_node_default_gateway=$admin_gateway" >>$tmp_config
echo >>$tmp_config

echo "dns_resolvers=$dns_resolver1,$dns_resolver2" >>$tmp_config
echo "dns_domain=$dns_domain" >>$tmp_config
echo >>$tmp_config

echo "# These are the dhcp settings for compute nodes on the admin network"\
    >>$tmp_config
echo "dhcp_range_start=$dhcp_range_start" >>$tmp_config
echo "dhcp_range_end=$dhcp_range_end" >>$tmp_config
echo "dhcp_lease_time=86400" >>$tmp_config
echo "dhcp_next_server=$dhcp_next_server" >>$tmp_config
echo >>$tmp_config

echo "# This should not be changed." >>$tmp_config
echo "initial_script=scripts/headnode.sh" >>$tmp_config
echo >>$tmp_config

echo "# This is the entry from /etc/shadow for root" >>$tmp_config
root_shadow=$(/usr/lib/cryptpass "$root_shadow")
echo "root_shadow='${root_shadow}'" >>$tmp_config
echo >>$tmp_config

#
# Currently we're using the same pw as we use for zones, but we may want
# to add another prompt for this as a 3rd pw.
#
echo "# This is the entry from /etc/shadow for the admin user" >>$tmp_config
admin_shadow=$(/usr/lib/cryptpass "$zone_admin_pw")
echo "admin_shadow='${admin_shadow}'" >>$tmp_config
echo >>$tmp_config

echo "ntp_hosts=$ntp_hosts" >>$tmp_config

echo "compute_node_ntp_hosts=$admin_ip" >>$tmp_config
echo >>$tmp_config

#
# The zone configuration data
#

echo "# Zone-specific configs" >>$tmp_config
echo >>$tmp_config

echo "adminui_admin_ip=$adminui_admin_ip" >>$tmp_config
echo "adminui_external_ip=$adminui_external_ip" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# adminui_external_vlan=0" >>$tmp_config
else
	echo "adminui_external_vlan=$external_vlan_id" >>$tmp_config
fi
echo "adminui_root_pw=$zone_admin_pw" >>$tmp_config
echo "adminui_admin_pw=$zone_admin_pw" >>$tmp_config
echo "adminui_help_url=http://wiki.joyent.com/display/sdc/Overview+of+SmartDataCenter" >>$tmp_config
echo >>$tmp_config

echo "assets_admin_ip=$assets_admin_ip" >>$tmp_config
echo "assets_root_pw=$zone_admin_pw" >>$tmp_config
echo "assets_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "ca_admin_ip=$ca_admin_ip" >>$tmp_config
echo "ca_client_url=$ca_client_url" >>$tmp_config
echo "ca_root_pw=$zone_admin_pw" >>$tmp_config
echo "ca_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "capi_is_local=true" >>$tmp_config
echo "capi_admin_ip=$capi_admin_ip" >>$tmp_config
echo "capi_client_url=$capi_client_url" >>$tmp_config
echo "capi_external_ip=$capi_external_ip" >>$tmp_config
echo "capi_external_url=$capi_external_url" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# capi_external_vlan=0" >>$tmp_config
else
	echo "capi_external_vlan=$external_vlan_id" >>$tmp_config
fi
echo "capi_root_pw=$zone_admin_pw" >>$tmp_config
echo "capi_http_admin_user=admin" >>$tmp_config
echo "capi_http_admin_pw=$http_admin_pw" >>$tmp_config
echo "capi_admin_login=admin" >>$tmp_config
echo "capi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "capi_admin_email=user@${domainname}" >>$tmp_config
echo "capi_admin_uuid=930896af-bf8c-48d4-885c-6573a94b1853" >>$tmp_config
echo >>$tmp_config

echo "dhcpd_admin_ip=$dhcpd_admin_ip" >>$tmp_config
echo "dhcpd_root_pw=$zone_admin_pw" >>$tmp_config
echo "dhcpd_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "dnsapi_http_port=8000" >>$tmp_config
echo "dnsapi_http_user=admin" >>$tmp_config
echo "dnsapi_http_pass=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "dsapi_url=https://datasets.joyent.com" >>$tmp_config
echo "dsapi_http_user=honeybadger" >>$tmp_config
echo "dsapi_http_pass=IEatSnakes4Fun" >>$tmp_config
echo >>$tmp_config

echo "mapi_admin_ip=$mapi_admin_ip" >>$tmp_config
echo "mapi_client_url=$mapi_client_url" >>$tmp_config
echo "mapi_root_pw=$zone_admin_pw" >>$tmp_config
echo "mapi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "mapi_mac_prefix=90b8d0" >>$tmp_config
echo "mapi_http_port=8080" >>$tmp_config
echo "mapi_http_admin_user=admin" >>$tmp_config
echo "mapi_http_admin_pw=$http_admin_pw" >>$tmp_config
echo "mapi_datasets=\"smartos,nodejs\"" >>$tmp_config
echo >>$tmp_config

# echo "portal_admin_ip=$portal_admin_ip" >>$tmp_config
echo "portal_external_ip=$portal_external_ip" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# portal_external_vlan=0" >>$tmp_config
else
	echo "portal_external_vlan=$external_vlan_id" >>$tmp_config
fi
echo "portal_root_pw=$zone_admin_pw" >>$tmp_config
echo "portal_admin_pw=$zone_admin_pw" >>$tmp_config
echo "portal_external_url=$portal_external_url" >>$tmp_config
echo >>$tmp_config

echo "cloudapi_admin_ip=$cloudapi_admin_ip" >>$tmp_config
echo "cloudapi_external_ip=$cloudapi_external_ip" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# cloudapi_external_vlan=0" >>$tmp_config
else
	echo "cloudapi_external_vlan=$external_vlan_id" >>$tmp_config
fi
echo "cloudapi_root_pw=$zone_admin_pw" >>$tmp_config
echo "cloudapi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "cloudapi_external_url=$cloudapi_external_url" >>$tmp_config
echo >>$tmp_config

echo "rabbitmq_admin_ip=$rabbitmq_admin_ip" >>$tmp_config
echo "rabbitmq_root_pw=$zone_admin_pw" >>$tmp_config
echo "rabbitmq_admin_pw=$zone_admin_pw" >>$tmp_config
echo "rabbitmq=$rabbitmq" >>$tmp_config
echo >>$tmp_config

echo "billapi_admin_ip=$billapi_admin_ip" >>$tmp_config
echo "billapi_external_ip=$billapi_external_ip" >>$tmp_config
if [ -z "$external_vlan_id" ]; then
	echo "# billapi_external_vlan=0" >>$tmp_config
else
	echo "billapi_external_vlan=$external_vlan_id" >>$tmp_config
fi
echo "billapi_root_pw=$zone_admin_pw" >>$tmp_config
echo "billapi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "billapi_external_url=$billapi_external_url" >>$tmp_config
echo "billapi_http_admin_user=admin" >>$tmp_config
echo "billapi_http_admin_pw=$http_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "riak_admin_ip=$riak_admin_ip" >>$tmp_config
echo "riak_root_pw=$zone_admin_pw" >>$tmp_config
echo "riak_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "phonehome_automatic=true" >>$tmp_config

echo
echo "Your configuration is about to be applied."
promptval "Would you like to edit the final configuration file?" "n"
[ "$val" == "y" ] && vi $tmp_config

clear
echo "The headnode will now finish configuration and reboot. Please wait..."
mv $tmp_config $USBMNT/config
