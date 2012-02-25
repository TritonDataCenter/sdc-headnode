#!/usr/bin/bash

# Globals
export PATH=/usr/sbin:/usr/bin:/opt/local/bin
export TERM=xterm-color

EULA_FILE=/var/tmp/EULA.txt
CONFIG=/var/tmp/setup.log
if [ -f $CONFIG ] ; then
  mv $CONFIG $CONFIG-old
  touch $CONFIG
fi

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

: ${DIALOG_INPUT=0}
: ${DIALOG_PASSWD=1}
: ${DIALOG_LABEL=2}

# Extra FDs
exec 3>&1 4>&2 

. network-include.sh

CONFIG_COMPANY=''
CONFIG_DCID=''
CONFIG_CITY=''
CONFIG_STATE=''
CONFIG_HOSTNAME=''
CONFIG_DOMAIN=''
CONFIG_NET_IPADDR=''
CONFIG_NET_IPMASK=''
CONFIG_NET_IPGW=''
CONFIG_DNS1='' 
CONFIG_DNS2='' 
CONFIG_DNS_SEARCH=''
CONFIG_NTP=''
CONFIG_PHONEHOME=false

# This list is an easier way of iterating
# through all the different config values
# and writing them out for testing
config_vars=( CONFIG_COMPANY CONFIG_DCID \
  CONFIG_CITY CONFIG_STATE CONFIG_HOSTNAME \
  CONFIG_DOMAIN CONFIG_NET_IPADDR \
  CONFIG_NET_IPMASK CONFIG_NET_IPGW \
  CONFIG_DNS1 CONFIG_DNS2 CONFIG_DNS_SEARCH \
  CONFIG_NTP CONFIG_PHONEHOME )

next_function=''
title='SDC Setup - Welcome'

sigexit() {
  clear
  echo "Exiting SDC Setup..."
  exit 0
}

#trap sigexit EXIT SIGINT

set_callback() {
  next_function=$1
}

callback() {
  ${next_function} $@
}

set_title() {
  title=$(printf "SDC Setup - %s\n" "$@")
}

print_welcome() {
	set_title "Welcome"
  dialog --backtitle "$title" \
    --msgbox "This setup wizard will guide you through \
installing SDC to your server. \
You will have the option of editing your changes prior \
to applying the installation." 10 44
  
  if [ $? -eq $DIALOG_CANCEL ] ; then
    exit 1
  fi  

  callback

}

print_eula() {
  if [ ! -f $EULA_FILE ] ; then
    return 0 
  fi

	set_title "License Agreement"
  dialog --backtitle "$title" --begin 2 4 \
    --title "License Agreement" \
    --exit-label "AGREE" \
    --textbox $EULA_FILE 20 72
  
  if [ $? -eq $DIALOG_CANCEL ] ; then
    exit 1
  fi  

  callback
}

# helper function for a dialog box
required() {
  dialog --backtitle "$title" \
    --msgbox "The field \"$1\" is required" 5 40
  callback
}

# asks about datacenter information, company
# city and state. All required fields
setup_datacenter() {
  local out
  OLD=$IFS
  IFS=$'\n'

  set_title "Cloud & Datacenter"
  out=( $(dialog --backtitle "$title" \
   --visit-items \
   --mixedform "Cloud & Datacenter" 0 0 0 \
  "Company Name"  1 2 "$CONFIG_COMPANY" 1 16 24 20 0 \
  "Datacenter ID" 2 2 "$CONFIG_DCID"    2 16 24 20 0 \
  "City"          3 2 "$CONFIG_CITY"    3 16 24 30 0 \
  "State"         4 2 "$CONFIG_STATE"   4 16 24 30 0 \
   2>&1 1>&3 ) ) 

  if [ $? -eq $DIALOG_CANCEL ] ; then
   launch_menu
  fi

  CONFIG_COMPANY="${out[0]}"
  CONFIG_DCID="${out[1]}"
  CONFIG_CITY="${out[2]}"
  CONFIG_STATE="${out[3]}" 

  if [ -z $CONFIG_COMPANY ] ; then
    set_callback "setup_datacenter"
    required "company"
  fi
 
  if [ -z $CONFIG_DCID ] ; then
    set_callback "setup_datacenter"
    required "DCID"
  fi
  
  if [ -z $CONFIG_CITY ] ; then
    set_callback "setup_datacenter"
    required "city"
  fi

  if [ -z $CONFIG_STATE ] ; then
    set_callback "setup_datacenter"
    required "state"
  fi

  IFS=$OLDIFS
  #callback
}

# queries passwords from user
# if passwords match then they are turned into
# md5 shas and set into the config
get_passwords() {
  local out
  OLDIFS=$IFS
  IFS=$'\n'

	set_title "User Setup"
  out=( $(dialog --backtitle "$title" \
	  --visit-items \
	  --insecure \
	  --passwordform "User Setup" 14 40 6 \
	  "root password" 2 2 "" 3 2 32 32 \
	  "root password" 4 2 "" 5 2 32 32 \
    2>&1 1>&3 ) )

  

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  IFS=$OLDIFS
  callback
}

# queries hostname and domain name from the user
# both required fields, validation performed
set_hostname() {
  local out
	
  set_title "Hostname"
	out=$(dialog --backtitle "$title" \
	  --title "Set Hostname" --nocancel \
		--inputbox "Please enter hostname for this machine" 0 0 $(hostname) \
    2>&1 1>&3 )

	if [ $? -eq $DIALOG_CANCEL ] ; then
		launch_menu
	fi

  # TODO Validate 
  CONFIG_HOSTNAME=$out

  set_title "Domain Name"
	out=$(dialog --backtitle "$title" \
	  --title "Set Domain Name" --nocancel \
		--inputbox "Please enter Domain Name for this machine" 0 0 $(hostname) \
    2>&1 1>&3 )

	if [ $? -eq $DIALOG_CANCEL ] ; then
		launch_menu
	fi
  
  # TODO Validate
  CONFIG_DOMAIN=$out

  callback 
}

# presents a list of all physical devices on the system
# and prompts the user to select one for use as the 
# 'management' / 'admin' network. Only one network needs
# to be setup at install time
select_networks() {
  local out
  local interfaces
  
  set_title "Networking"
  interfaces=$(dladm show-phys -mo link,address | grep -v LINK | awk '{print $1 " "$2}')

	if [ -z "$interfaces" ] ; then
		dialog --backtitle "$title" \
		  --title "Network Configuration Error" \
			--msgbox "No network interfaces present to configure." 0 0
		exit 1
	fi

	out=$(echo $interfaces | xargs dialog --backtitle "$title" \
	  --title "Network Configuration" \
		--menu "Please select a network interface to configure: " 0 0 0 \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

	dialog --backtitle "$title" \
    --title "Network Configuration" \
    --yesno "Would you like to configure IPv4 for this interface?" 0 0
	
	if [ $? -eq $DIALOG_OK ] ; then
		netconfig_ipv4 $out
  else
    select_networks
	fi

}

# prompts for the ipv4 configuration of a particular interface
# This probably wont work until we're plumbing devices by default
netconfig_ipv4() {
  local interface
  local title
  local out
  local ipaddr
  local ip_mask
  local gateway 

  interface=$1
  set_title "Network Configuration"
  if [ -z "$interface" ] ; then
    dialog --backtitle "$title" \
      --title "Network Configuration Error" \
      --msgbox "No interface specified for IPv4 configuration." 0 0
    exit 1
  fi 

  gateway=$(netstat -rn -f inet | awk '/default/ {printf("%s\n", $2); }')
  ip_addr=$(ifconfig $interface | awk '/inet/ {printf("%s\n", $2); }')
  hex_mask=$(ifconfig $interface | awk '/inet/ {printf("%s\n", $4); }')
  ip_mask=$(hex_to_dotted $hex_mask)

  local OLDIFS=$IFS
  IFS=$'\n'

  out=( $(dialog --backtitle "$title" \
    --title "Network Configuration" \
    --form "Static Network Interface Configuration (IPv4)" 0 0 0 \
    "IP Address"      1 0 "$ip_addr" 1 20 16 0 \
    "Subnet Mask"     2 0 "$ip_mask" 2 20 16 0 \
    "Default Gateway" 3 0 "$gateway" 3 20 16 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu 
  fi  

  CONFIG_NET_IPADDR="${out[0]}"
  CONFIG_NET_IPMASK="${out[1]}"
  CONFIG_NET_IPGW="${out[2]}"

  IFS=$OLDIFS

  callback
}

# prompts for the ipv6 configuration of a particular interface
# This probably wont work until we're plumbing devices by default
# Not used
netconfig_ipv6() {
  local interface=$1
  set_title "Network Configuration"

  if [ -z "$interface" ] ; then
    dialog --backtitle "$title" \
      --title "Network Configuration Error" \
      --msgbox "No interface specified for IPv6 configuration." 0 0
    exit 1
  fi

  dialog --backtitle "$title" \
    --title "Network Configuration" \
    --yesno "Would you like to try stateless autoconfiguration (SLAAC)?" 0 0

  if [ $? -eq $DIALOG_OK ] ; then
    echo "Stateless configuration chosen" # XXX
    exit 0
  fi

  ip_addr=$(ifconfig $interface inet6) 

}

# prompts the user as to whether or not they want to be able to 
# automatically phone home for reporting issues / usage / etc
set_phonehome() {
  local title
  local out

  set_title "Help & Troubleshooting"

  out=$(dialog --backtitle "$title" \
    --title "Help & Troubleshooting" \
    --yesno "SDC can automatically report usage and issues to Joyent on
a periodic basis. This information is kept strictly confidential and is
only used to improve future versions of SDC.\n\n 
Would you like to automatically report issues to Joyent?" 0 0 \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_OK ] ; then
    echo "true"
  else
    echo "false"
  fi

  callback 

}

# dns nameservers and local search domain
# validated and required
set_resolvers() {
  set_title "Network Configuration"
  local resolvers=$(awk '/nameserver/ {printf("%s\n", $2); }' /etc/resolv.conf)
  local search_domain=$(grep domain /etc/resolv.conf)

  if [ -z $search_domain ] ; then
    search_domain=$CONFIG_DOMAIN
  fi 

  local OLDIFS=$IFS
  IFS=$'\n'

  out=( $(dialog --backtitle "$title" \
    --title "Network Configuration" \
    --form "DNS Nameserver Configuration" 0 0 0 \
    "DNS Server 1 IP" 1 0 "${resolvers[0]}" 1 20 16 0 \
    "DNS Server 2 IP" 2 0 "${resolvers[1]}" 2 20 16 0 \
    "Search Domain" 4 0 "$search_domain" 4 20 24 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  CONFIG_DNS1="${out[0]}"
  CONFIG_DNS2="${out[1]}"
  CONFIG_DNS_SEARCH="${out[2]}"

  IFS=$OLDIFS
  callback
}

# NTP client configuration. NTP server is queried using dig and
# if validated / reachable is stored in the config
set_ntp() {
	set_title "NTP Configuration"
	
  out=$(dialog --backtitle "$title" \
	  --title "NTP Client Configuration" --nocancel \
		--inputbox "Please specify an NTP Server" 0 0 "$CONFIG_NTP" \
    2>&1 1>&3 )

	if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
	fi

  #TODO dig this and save the IP address
  CONFIG_NTP="${out}"

  callback
}

# prints the services menu which is used to configure individual zones
# zones automatically have their configuration populated after the
# initial network configuration is completed
services_menu() {
  set_callback "expert_menu" # return to menu after selection complete
  set_title "Services (expert)"
  
  out=$(dialog --backtitle "$title" \
    --title "Services Configuration Menu" \
    --cancel-label "Back" \
    --menu "Please select one of the configuration options" 0 0 0 \
    "mapi"   "$(printf "%-22s %8s" "Master API" "")" \
    "assets" "$(printf "%-22s %8s" "Static Assets Server" "")" \
    "dhcpd"  "$(printf "%-22s %8s" "Management DHCP Daemon" "")" \
    "amqp"   "$(printf "%-22s %8s" "AMQP Message Bus" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    expert_menu
  fi

  case $out in
    mapi)
      ;;
    assets)
      ;;
    dhcpd)
      ;;
    amqp)
      ;;
  esac
}

# expert menu which acts as the entry point to manual edit and the
# services / zone configuration menu. this buries it just a little bit
# and also has that "feel good" affect (everyone is an expert)
expert_menu() {
  set_callback "expert_menu" # return to menu after selection complete
  set_title "Expert Mode"
  
  out=$(dialog --backtitle "$title" \
    --title "Services Configuration Menu" \
    --cancel-label "Back" \
    --menu "Please select one of the configuration options" 0 0 0 \
    "services"   "$(printf "%-22s %8s" "Configure Services"   "")" \
    "edit"       "$(printf "%-22s %8s" "Manually Edit Config" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  case $out in
    services)
      services_menu 
      ;;
    edit)
      vim /tmp/config
      callback
      ;;
  esac
}

# general launch menu. this menu is the default method of navigating
# all the configuration options and dialogs
launch_menu() {
  set_callback "launch_menu" # return to menu after selection complete
  set_title "Welcome"
  
  out=$(dialog --backtitle "$title" \
    --title "Configuration Menu" \
    --cancel-label "Quit" \
    --menu "Please select one of the configuration options" 0 0 0 \
    "datacenter" "$(printf "%-22s %8s" "Datacenter Information" "")" \
    "hostname"   "$(printf "%-22s %8s" "Hostname & Domain Name" "")" \
    "networks"   "$(printf "%-22s %8s" "Networking" "")" \
    "resolvers"  "$(printf "%-22s %8s" "DNS Resolvers" "")" \
    "ntp"        "$(printf "%-22s %8s" "Date & Time" "")" \
    "phonehome"  "$(printf "%-22s %8s" "Feedback Support" "")" \
    "expert"     "$(printf "%-22s %8s" "Expert Menu" "")" \
    "rescue"     "$(printf "%-22s %8s" "Launch Rescue Shell" "")" \
    "apply"      "$(printf "%-22s %8s" "Save & Install" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    exit 1
  fi

  case $out in
    datacenter)
      setup_datacenter
      ;;
    hostname)
      set_hostname
      ;;
    networks)
      select_networks
      ;; 
    resolvers)
      set_resolvers
      ;;
    ntp)
      set_ntp
      ;;
    phonehome)
      set_phonehome
      ;;
    expert)
      expert_menu
      ;;
    rescue)
      clear
      echo "Launching emergency rescue shell..."
      bash 
      callback
      ;;
    apply)
      apply_config
      ;;
  esac

}

# helper for writing config to some location specified by the
# CONFIG variable
write_config() {
  echo "${@}" >> $CONFIG
}

# helper for applying configuration
apply_config() {
  local title
  local out

  set_title "Apply & Install"
  out=$(dialog --backtitle "$title" \
    --yesno "Apply configuration & Install SDC?" 0 0 \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_OK ] ; then
    echo "Applying configuration"
    for c in ${config_vars[@]}; do
      write_config "$c=`eval $c`"
    done
    exit 0
  else
    launch_menu
  fi

}


# Main
print_welcome
print_eula
setup_datacenter
#set_hostname
#select_networks
#set_resolvers
#set_ntp
#set_phonehome
#apply_config

