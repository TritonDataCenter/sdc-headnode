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
	if [ $2 -eq 255 ]; then
		fmax=$1
	else
		fmax=$((255 & ~$2))
	fi
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
	val=
	printf "%s [press enter for none]: " "$1"
	read val
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
	while [ /usr/bin/true ]; do
		val=""
		while [ -z "$val" ]; do
			printf "%s: " "$1"
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
				echo "A value must be provided."
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
  for i in {1..80} ; do printf "-" ; done && printf "$newline"
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
flows between the Compute Nodes and the Headnode in an SDC cluster. The Admin
network will be used to automatically provision new compute nodes. It is
important that the Admin network be used exclusively for SDC management. 
Please note that DHCP traffic will be present on this network following the 
installation. The Admin network is connected in VLAN ACCESS mode only.\n\n"
  
	printf "$message"
	
	promptnic "'admin'"
	admin_nic="$val"

	promptnet "(admin) headnode IP address" "$admin_ip"
	admin_ip="$val"

	promptnet "(admin) headnode netmask" "$admin_netmask"
	admin_netmask="$val"

	printheader "Networking - External"
	message="
The external network is used by the headnode and its applications to connect to
external networks. That is, it can be used to communicate with either the
Internet, an intranet, or any other WAN.\n\n"
  
	printf "$message"

	promptnic "'external'"
	external_nic="$val"

	promptnet "(external) headnode IP address" "$external_ip"
	external_ip="$val"

	promptnet "(external) headnode netmask" "$external_netmask"
	external_netmask="$val"

	promptopt "(external) VLAN ID"
	external_vlan_id="$val"

	if [[ -z "$external_provisionable_start" ]]; then
		ip_netmask_to_network "$external_ip" "$external_netmask"
		next_addr=$(expr $host_addr + 1)
		external_provisionable_start="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
		external_provisionable_end="$max_host"
	fi
	promptnet "Starting provisionable IP address" \
	   "$external_provisionable_start"
	external_provisionable_start="$val"

	promptnet "Ending provisionable IP address" \
	   "$external_provisionable_end"
	external_provisionable_end="$val"

	printheader "Networking - Continued"
	message=""
  
	printf "$message"

	message="
The default gateway will determine which network will be used to connect to
other networks. This will almost certainly be the router connected to your
'External' network.\n\n"

	printf "$message"

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
There are two primary accounts for managing a Smart Data Center. 
These are 'admin', and 'root'. Each user can have a unique password. Most of 
the interaction you will have with SDC will be using the 'admin' user, unless
otherwise specified. SDC also has the ability to send notification emails to a
specific address. Each of these values will be configured below.\n\n"

	printf "$message"
	
	promptpw "Enter root password" "nolen"
	root_shadow="$val"
	
	promptpw "Enter admin password" "chklen"
	zone_admin_pw="$val"
	
	promptemail "Administrator email goes to" "$mail_to"
	mail_to="$val"

	[[ -z "$mail_from" ]] && mail_from="support@${domainname}"
	promptemail "Support email should appear from" "$mail_from"
	mail_from="$val"

	printheader "Verify Configuration"
	message=""
  
	printf "$message"

	echo "Verify that the following values are correct:"
	echo
	echo "Company name: $datacenter_company_name"
	echo "Datacenter name: $datacenter_name"
	echo "Datacenter location: $datacenter_location"
	echo "Headnode ID: $datacenter_headnode_id"
	echo "Administrator email address: $mail_to"
	echo "Email appears from: $mail_from"
	echo "Domain name: $domainname"
	echo "Admin network MAC address: $admin_nic"
	echo "Admin network IP address: $admin_ip"
	echo "Admin network netmask: $admin_netmask"
	echo "External network MAC address: $external_nic"
	echo "External network IP address: $external_ip"
	echo "External network netmask: $external_netmask"
	if [ -z "$external_vlan_id" ]; then
		echo "External network VLAN ID: [none]"
	else
		echo "External network VLAN ID: $external_vlan_id"
	fi
	echo "Starting provisionable IP address: $external_provisionable_start"
	echo "Ending provisionable IP address: $external_provisionable_end"
	echo "Gateway router IP address: $headnode_default_gateway"
	echo "DNS servers: $dns_resolver1,$dns_resolver2"
	echo "Default DNS search domain: $dns_domain"
	echo "NTP server: $ntp_hosts"
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
next_addr=$(expr $host_addr + 1)
adminui_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
next_addr=$(expr $next_addr + 1)
assets_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
next_addr=$(expr $next_addr + 1)
atropos_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
next_addr=$(expr $next_addr + 1)
ca_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
ca_client_url="http://${ca_admin_ip}:23181"
next_addr=$(expr $next_addr + 1)
capi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
capi_client_url="http://${capi_admin_ip}:8080"
next_addr=$(expr $next_addr + 1)
dhcpd_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
next_addr=$(expr $next_addr + 1)
mapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
mapi_client_url="http://${mapi_admin_ip}:80"
next_addr=$(expr $next_addr + 1)
portal_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
portal_external_url="https://${portal_admin_ip}"
next_addr=$(expr $next_addr + 1)
cloudapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
cloudapi_external_url="https://${cloudapi_admin_ip}"
next_addr=$(expr $next_addr + 1)
pubapi_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
pubapi_client_url="http://${pubapi_admin_ip}:8080/v1"
next_addr=$(expr $next_addr + 1)
rabbitmq_admin_ip="$net_a.$net_b.$net_c.$(expr $net_d + $next_addr)"
rabbitmq="guest:guest:${rabbitmq_admin_ip}:5672"

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
echo "admin_gateway=$admin_ip" >>$tmp_config
echo >>$tmp_config

echo "# external_nic is the nic external_ip will be connected to for headnode zones." \
    >>$tmp_config
echo "external_nic=$external_nic" >>$tmp_config
echo "external_ip=$external_ip" >>$tmp_config
echo "external_gateway=$headnode_default_gateway" >>$tmp_config
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
echo "compute_node_default_gateway=$admin_ip" >>$tmp_config
echo >>$tmp_config

echo "dns_resolvers=$dns_resolver1,$dns_resolver2" >>$tmp_config
echo "dns_domain=$dns_domain" >>$tmp_config
echo >>$tmp_config

echo "# These are the dhcp settings for compute nodes on the admin network"\
    >>$tmp_config
echo "dhcp_range_start=$dhcp_range_start" >>$tmp_config
echo "dhcp_range_end=$dhcp_range_end" >>$tmp_config
echo "dhcp_lease_time=6000" >>$tmp_config
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
echo "adminui_root_pw=$zone_admin_pw" >>$tmp_config
echo "adminui_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "assets_admin_ip=$assets_admin_ip" >>$tmp_config
echo "assets_root_pw=$zone_admin_pw" >>$tmp_config
echo "assets_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "atropos_admin_ip=$atropos_admin_ip" >>$tmp_config
echo "atropos_root_pw=$zone_admin_pw" >>$tmp_config
echo "atropos_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "ca_admin_ip=$ca_admin_ip" >>$tmp_config
echo "ca_client_url=$ca_client_url" >>$tmp_config
echo "ca_root_pw=$zone_admin_pw" >>$tmp_config
echo "ca_admin_pw=$zone_admin_pw" >>$tmp_config
echo >>$tmp_config

echo "capi_is_local=true" >>$tmp_config
echo "capi_admin_ip=$capi_admin_ip" >>$tmp_config
echo "capi_client_url=$capi_client_url" >>$tmp_config
echo "capi_root_pw=$zone_admin_pw" >>$tmp_config
echo "capi_http_admin_user=admin" >>$tmp_config
echo "capi_http_admin_pw=tot@ls3crit" >>$tmp_config
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
echo "mapi_http_admin_pw=tot@ls3crit" >>$tmp_config
echo "mapi_datasets=\"smartos,nodejs\"" >>$tmp_config
echo >>$tmp_config

echo "portal_admin_ip=$portal_admin_ip" >>$tmp_config
echo "portal_root_pw=$zone_admin_pw" >>$tmp_config
echo "portal_admin_pw=$zone_admin_pw" >>$tmp_config
echo "portal_external_url=$portal_external_url" >>$tmp_config
echo >>$tmp_config

echo "cloudapi_admin_ip=$cloudapi_admin_ip" >>$tmp_config
echo "cloudapi_root_pw=$zone_admin_pw" >>$tmp_config
echo "cloudapi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "cloudapi_external_url=$cloudapi_external_url" >>$tmp_config
echo >>$tmp_config

echo "pubapi_admin_ip=$pubapi_admin_ip" >>$tmp_config
echo "pubapi_client_url=$pubapi_client_url" >>$tmp_config
echo "pubapi_root_pw=$zone_admin_pw" >>$tmp_config
echo "pubapi_admin_pw=$zone_admin_pw" >>$tmp_config
echo "pubapi_default_datacenter=$datacenter_name" >>$tmp_config
echo >>$tmp_config

echo "rabbitmq_admin_ip=$rabbitmq_admin_ip" >>$tmp_config
echo "rabbitmq_root_pw=$zone_admin_pw" >>$tmp_config
echo "rabbitmq_admin_pw=$zone_admin_pw" >>$tmp_config
echo "rabbitmq=$rabbitmq" >>$tmp_config
echo >>$tmp_config

echo "phonehome_automatic=true" >>$tmp_config

echo
echo "Your configuration is about to be applied."
promptval "Would you like to edit the final configuration file?" "n"
[ "$val" == "y" ] && vi $tmp_config

clear
echo "The headnode will now finish configuration and reboot. Please wait..."
mv $tmp_config $USBMNT/config
