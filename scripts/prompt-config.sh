#!/usr/bin/bash

# Todo
# * detect IP address in use
# * add built-in help

# Globals
PREFIX=/tmp

export PATH=/usr/sbin:/usr/bin:/opt/local/bin
export TERM=sun-color
export DIALOGRC=$PREFIX/dialogrc

if [ $# -ne 1 ] ; then
	echo "usage: $0 <usbmountpoint>"
	exit 1
fi

USBMNT=$1
EULA_FILE=$PREFIX/EULA
CONFIG=$PREFIX/setup.out
OLDCONFIG=$USBMNT/config
LOG=$PREFIX/setup.log

if [ -f $CONFIG ] ; then
  mv $CONFIG $CONFIG-old
  touch $CONFIG
fi

if [ -f $OLDCONFIG ] ; then
  mv $OLDCONFIG $OLDCONFIG-old
  touch $OLDCONFIG
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

CONFIG_COMPANY=''
CONFIG_DCID=''
CONFIG_CITY=''
CONFIG_STATE=''
CONFIG_FQDN=''
CONFIG_DOMAIN=''
CONFIG_HOSTNAME=''
CONFIG_NET_IPADDR=''
CONFIG_NET_IPMASK=''
CONFIG_NET_IPNET=''
CONFIG_NET_IPGW=''
CONFIG_NET_IFNAME=''
CONFIG_NET_MACADDR=''
CONFIG_DNS1=''
CONFIG_DNS2=''
CONFIG_DNS_SEARCH=''
CONFIG_NTP_HOST='pool.ntp.org'
CONFIG_NTP_IPADDR=''
CONFIG_PHONEHOME=false
CONFIG_PASS_ROOT=''
CONFIG_PASS_ADMIN=''
CONFIG_PASS_API=''
CONFIG_KEYBOARD='US-English'
CONFIG_MAPI_NET_IPADDR=''
CONFIG_ASSETS_NET_IPADDR=''
CONFIG_AMQP_NET_IPADDR=''
CONFIG_DHCP_NET_IPADDR=''
CONFIG_DHCP_START=''
CONFIG_DHCP_STOP=''

STATUS_NET_IS_SETUP=1
STATUS_NTP_IS_SETUP=1
STATUS_DNS_IS_SETUP=1
STATUS_FQDN_IS_SETUP=1
STATUS_DC_IS_SETUP=1
STATUS_PASS_ROOT_IS_SETUP=1
STATUS_PASS_ADMIN_IS_SETUP=1
STATUS_PASS_API_IS_SETUP=1

# all the different config, status, and IP address values
config_vars=$( set -o posix ; set | awk -F= '/^CONFIG_/ {print $1}')
status_vars=$( set -o posix ; set | awk -F= '/^STATUS_/ {print $1}')
ipaddr_vars=$( set -o posix ; set | awk -F= '/_NET_IPADDR$/ {print $1}')

trap sigexit EXIT SIGINT

next_function=''   # if you exit dialog youre on previous selection
last_menu_item=''  # ^
title='SDC Setup - Welcome'

##############################################
# Helper functions
##############################################

check_setup() {
  local retval=0
  local label=''
  local token=''

  for c in ${status_vars[@]}; do
    loginfo "Checking value: $c"
    if [[ ${!c} -eq 1 ]] ; then
      case $c in
        STATUS_NET_IS_SETUP)
          label="Admin Network"
          break
          ;;
        STATUS_NTP_IS_SETUP)
          label="NTP"
          break
          ;;
        STATUS_DNS_IS_SETUP)
          label="DNS"
          break
          ;;
        STATUS_FQDN_IS_SETUP)
          label="Hostname"
          break
          ;;
        STATUS_DC_IS_SETUP)
          label="Datacenter"
          break
          ;;
        STATUS_PASS_ROOT_IS_SETUP)
          label="Root password"
          break
          ;;
        STATUS_PASS_ADMIN_IS_SETUP)
          label="Admin password"
          break
          ;;
        STATUS_PASS_API_IS_SETUP)
          label="API password"
          ;;
      esac

      retval=1
      break
    fi
  done

  msg="$label setup is not complete\nPlease review your configuration"
  loginfo "check lablel: $label"
  [[ ! -z $label ]] && warn "$msg" "launch_menu"

}

sigexit() {
  clear
  echo "Exiting SDC Setup..."
  exit 0
}

loginfo() {
  local stamp=$(date +%Y-%m-%dT%H:%MZ)
  printf "%-17s (info) %s\n" $stamp "$@" >> $LOG
}

set_callback() {
  loginfo "setting callback to $1"
  next_function=$1
}

set_last_item() {
  loginfo "setting last menu item to $1"
  last_menu_item=$1
}

set_title() {
  title=$(printf "SDC Setup - %s\n" "$@")
}

callback() {
  loginfo "running callback $1"
  ${next_function} $@
}

warn() {
  dialog --backtitle "$title" --msgbox "$1" 0 0
  eval $2
}

write_config() {
  echo "Applying configuration..."
  for c in ${config_vars[@]}; do
    echo "$c=${!c}" >> $CONFIG
  done
  exit 0
}

__wr() {
  echo "$@" >> $OLDCONFIG
}

__is_vmware() {
  platform=$(smbios -t1 | awk '/Product:/ {print $2}')
  [[ "$platform" == "VMware" ]] && return 0
  return 1
}

__max_fld() {
	comp=$((255 & ~$2))
	fmax=$(($comp | $1))
}

__isdigit() {
  [[ $# -eq 1 ]] || return 1

  case $1 in
    *[!0-9]*|"")
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

__hex_to_dotted() {
  printf "%d.%d.%d.%d\n" $(echo $1 | sed 's/../ 0x&/g')
}

__ip_to_dec() {
  ip=( $(printf "%d\n%d\n%d\n%d\n" $(echo $1 | sed 's/\./ /g')) )
  out=$(( (${ip[0]} << 24) | (${ip[1]} << 16) | (${ip[2]} << 8) | ${ip[3]} ))
  echo $out
}

__ip_mask_to_net() {
  # ip = $1, netmask = $2
  ip=$(__ip_to_dec $1)
  mask=$(__ip_to_dec $2)
  net=$(($ip & $mask)) # in decimal
  out=( $(($net >> 24)) $(($net >> 16 & 255)) $(($net >> 8 & 255)) $(($net & 255)) )
  printf "%d.%d.%d.%d\n" "${out[@]}"

}

__dec_to_ip() {
  net=$1
  out=( $(($net >> 24)) $(($net >> 16 & 255)) $(($net >> 8 & 255)) $(($net & 255)) )
  printf "%d.%d.%d.%d\n" "${out[@]}"
}

__is_ip() {
  regex="^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$";

  [[ $1 =~ $regex ]] && return 0
  return 1
}

__is_hostname() {
  regex="^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])$";

  [[ $1 =~ $regex ]] && return 0
  return 1
}

__is_cidr() {
  regex="^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(\d[1-2]\d|3[0-2]))$";

  [[ $1 =~ $regex ]] && return 0
  return 1
}

__is_in_net() {
  # network = $1, mask =$2, to_check = $3
  checknet=$(__ip_mask_to_net $3 $2)
  [[ "$checknet" == "$1" ]] && return 0
  return 1
}

__net_size() {
 dec=$(__ip_to_dec $1)
 ipv4_size=4294967296
 printf "%d\n" $(( $ipv4_size - $dec -1 ))
}

##############################################
# Dialogs - These are ran by menus or by flow
##############################################

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

}

print_eula() {
  if [ ! -f $EULA_FILE ] ; then
    return 0
  fi

  set_title "License Agreement"

  dialog --backtitle "$title" --begin 2 4 \
    --title "License Agreement" \
    --exit-label "I AGREE" \
    --textbox $EULA_FILE 20 72

  if [ $? -eq $DIALOG_CANCEL ] ; then
    exit 1
  fi

}


list_kbd_layouts() {
  local kbd_layouts=/usr/share/lib/keytables/type_6/kbd_layouts
  local kbds=$(cat $kbd_layouts | sed -e '/^$/d;/^#/d')
  local count=0
  for i in ${kbds[@]} ; do
    OLDIFS=$IFS
    IFS=$'='
    a=( $i )
    ((count++))
    printf "%s %s\n" $count ${a[0]}
    IFS=$OLDIFS
  done

  loginfo "got keyboard information: $count"

}


setup_kbd() {
  local out
  set_title "Keyboard Layout"

  keyboards=$(list_kbd_layouts)
  out=$(echo $keyboards | xargs dialog --backtitle "$title" \
    --default-item 47 \
    --menu "Please select a keyboard layout" 15 40 10\
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  kbd=$(echo $keyboards | grep $out | cut -d ' ' -f2)
  loginfo "setting keyboard to: $kbd"
  CONFIG_KEYBOARD=$kbd
  kbd -s $kbd 2>&1 > /dev/null

  callback
}


# asks about datacenter information, company
# city and state. All required fields
setup_datacenter() {
  local out

  set_title "Datacenter"

  OLDIFS=$IFS
  IFS=$'\n'

  out=( $(dialog --backtitle "$title" \
   --visit-items \
   --mixedform "Datacenter" 0 0 0 \
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

  IFS=$OLDIFS

  loginfo "company: $CONFIG_COMPANY"
  loginfo "dcid: $CONFIG_DCID"
  loginfo "city: $CONFIG_CITY"
  loginfo "state: $CONFIG_STATE"

  if [ -z $CONFIG_COMPANY ] ; then
    warn "Company is required" setup_datacenter
  fi

  if [ -z $CONFIG_DCID ] ; then
    warn "Datacenter ID is required" setup_datacenter
  fi

  if [ -z $CONFIG_CITY ] ; then
    warn "City is required" setup_datacenter
  fi

  if [ -z $CONFIG_STATE ] ; then
    warn "State is required" setup_datacenter
  fi

  STATUS_DC_IS_SETUP=0

  callback
}


set_password() {
  local out

  # we use the username arg to set these key variables
  # ie
  # STATUS_PASS_API_IS_SETUP=1
  # CONFIG_PASS_API=''

  status_key="STATUS_PASS_$1_IS_SETUP"
  config_key="CONFIG_PASS_$1"

  set_title "User Setup"

  OLDIFS=$IFS
  IFS=$'\n'

  out=( $(dialog --backtitle "$title" \
    --visit-items \
    --insecure \
    --passwordform "Set Password ($1)" 14 40 6 \
    "password" 2 2 "" 3 2 32 32 \
    "confirmation" 4 2 "" 5 2 32 32 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    callback
  fi

  one="${out[0]}"
  two="${out[1]}"
  IFS=$OLDIFS

  if [ "${one}" == "${two}" ] ; then
    if [ "${#one}" -lt 6 ] ; then
      warn "Password must be at least 6 characters long" "set_password $1"
    else
      loginfo "password set to ${one}"
      eval $config_key="${one}"
    fi
  else
		warn "Passwords do not match" "set_password $1"
  fi

  loginfo "status key is $status_key"
  eval $status_key=0
  callback

}


# queries hostname and domain name from the user
# both required fields, validation performed
set_fqdn() {
  local out

  set_title "Hostname"

  out=$(dialog --backtitle "$title" \
    --title "Set Hostname" --nocancel \
    --inputbox "Please enter the fully qualified domain name (FQDN) \
for this machine" 0 0 $(hostname) \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  [[ -z $out ]] && warn "FQDN cannot be empty" set_fqdn

  # bash missing an array join
  CONFIG_FQDN=$out

  split=( $(echo $out | sed 's/\./ /g') )
  CONFIG_HOSTNAME="${split[0]}"
  unset split[0]
  CONFIG_DOMAIN=$(echo "${split[@]}" | sed 's/ /\./g')

  if [ -z $CONFIG_FQDN ] ; then
    warn "Does not appear to be a FQDN\nMust be in form \"hostname.domainname\"" set_fqdn
  fi

  if [ -z $CONFIG_DNS_SEARCH ] ; then
    CONFIG_DNS_SEARCH=$CONFIG_DOMAIN
  fi

  loginfo "$(hostname $CONFIG_FQDN)"
  STATUS_FQDN_IS_SETUP=0

  callback
}


# presents a list of all physical devices on the system
# and prompts the user to select one for use as the
# 'management' / 'admin' network. Only one network needs
# to be setup at install time
select_networks() {
  local out
  local interfaces
  local nics
  local states

  set_title "Networking"

  OLDIFS=$IFS
  IFS=$'\n'

  nics=( $(dladm show-phys -mo link,address | grep -v ^LINK ) )
  states=( $(dladm show-phys -po state) )
  interfaces=''

  IFS=$OLDIFS

  if [ -z "$nics" ] ; then
    dialog --backtitle "$title" \
      --title "Network Configuration Error" \
      --msgbox "No network interfaces present to configure." 0 0
    exit 1
  fi

  for (( i=0; i<${#nics[@]}; i++ )) ; do
    link=$( echo ${nics[$i]} | awk '{print $1}' )
    addr=$( echo ${nics[$i]} | awk '{print $2}' )
    interfaces="$interfaces $link \"$addr  ${states[$i]}\""
  done

  # iterate through interfaces and mark the currently used
  # admin interface with an asterisk
  if [ ! -z $CONFIG_NET_IFNAME ] ; then
    ints=$(echo $interfaces | sed "s/$CONFIG_NET_IFNAME/$CONFIG_NET_IFNAME*/")
  else
    ints=$interfaces
  fi

  out=$(echo $ints | xargs dialog --backtitle "$title" \
    --visit-items \
    --title "Network Configuration" \
    --menu "Please select a management network interface to configure: " 16 50 8 \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  # remove our identifying asterisk
  netconfig_ipv4 $(echo $out | sed 's/*//')

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
  set_title "Network Configuration ($interface)"
  if [ -z "$interface" ] ; then
    dialog --backtitle "$title" \
      --title "Network Configuration Error" \
      --msgbox "No interface specified for IPv4 configuration." 0 0
    exit 1
  fi

  loginfo "$(ifconfig $interface plumb 2>&1)"

  gateway=$(netstat -rn -f inet | awk '/default/ {printf("%s\n", $2); }')
  ip_addr=$(ifconfig $interface | awk '/inet/ {printf("%s\n", $2); }')
  hex_mask=$(ifconfig $interface | awk '/inet/ {printf("%s\n", $4); }')
  mac_addr=$(dladm show-phys -mo address $interface | grep -v ^ADDRESS)
  ip_mask=$(__hex_to_dotted "$hex_mask")

  [[ $ip_addr == "0.0.0.0" ]] && ip_addr=""
  [[ $ip_mask == "0.0.0.0" ]] && ip_mask=""
  [[ $gateway == "0.0.0.0" ]] && gateway=""

  out=( $(dialog --backtitle "$title" \
    --visit-items \
    --title "Network Configuration" \
    --form "Static Network Configuration (IPv4)" 0 0 0 \
    "MAC Address"     1 0 "$mac_addr"  1 20  0 0 \
    "VLAN"            2 0 "0 (native)" 2 20  0 0 \
    "IP Address"      3 0 "$ip_addr"   3 20 16 0 \
    "Subnet Mask"     4 0 "$ip_mask"   4 20 16 0 \
    "Default Gateway" 6 0 "$gateway"   6 20 16 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    select_networks
  fi

  CONFIG_NET_MACADDR="$mac_addr"
  CONFIG_NET_IFNAME="$interface"
  CONFIG_NET_IPADDR="${out[0]}"
  CONFIG_NET_IPMASK="${out[1]}"
  CONFIG_NET_IPGW="${out[2]}"

  __is_ip "$CONFIG_NET_IPADDR" || warn \
    "$CONFIG_NET_IPADDR is not a valid IP" "netconfig_ipv4 $interface"

  __is_ip "$CONFIG_NET_IPMASK" || warn \
    "$CONFIG_NET_IPMASK is not a valid Netmask" "netconfig_ipv4 $interface"

  __is_ip "$CONFIG_NET_IPGW" || warn \
    "$CONFIG_NET_IPGW is not a valid Gateway" "netconfig_ipv4 $interface"

  [[ $(__net_size $CONFIG_NET_IPMASK) -lt 32 ]] && warn \
    "Network too small\nMust have at least 32 hosts"

  CONFIG_NET_IPNET=$(__ip_mask_to_net $CONFIG_NET_IPADDR $CONFIG_NET_IPMASK)

  # we plumb the device immediately so the rest of the setup can conclude
  # with networking enabled
  loginfo "$(ifconfig $CONFIG_NET_IFNAME $CONFIG_NET_IPADDR netmask $CONFIG_NET_IPMASK up)"
  loginfo "$(route flush && route add -net 0/0 $CONFIG_NET_IPGW)"
  loginfo "$(route add -net 0/0 $CONFIG_NET_IPGW)"

  # set the rest of the service IP address values
  service_ip_start=$(( $(__ip_to_dec $CONFIG_NET_IPADDR) + 3 ))
  service_net_start=$(__ip_to_dec $CONFIG_NET_IPNET)
  service_net_size=$(__net_size $CONFIG_NET_IPMASK)

  CONFIG_ASSETS_NET_IPADDR=$(__dec_to_ip $(( $service_ip_start + 1 )) )
  CONFIG_DHCP_NET_IPADDR=$(__dec_to_ip $(( $service_ip_start + 2 )) )
  CONFIG_AMQP_NET_IPADDR=$(__dec_to_ip $(( $service_ip_start + 3 )) )
  CONFIG_MAPI_NET_IPADDR=$(__dec_to_ip $(( $service_ip_start + 4 )) )
  CONFIG_DHCP_START=$(__dec_to_ip $(( $service_ip_start + 5 )) )
  CONFIG_DHCP_STOP=$(__dec_to_ip $(( $service_net_start + $service_net_size - 1 )) )

  STATUS_NET_IS_SETUP=0
  callback
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
    CONFIG_PHONEHOME=true
  else
    CONFIG_PHONEHOME=false
  fi

  callback
}


# dns nameservers and local search domain
# validated and required
set_resolvers() {
  local out
  local resolvers
  local search_domain

  set_title "Network Configuration"
  resolvers=( $(awk '/nameserver/ {printf("%s\n", $2); }' /etc/resolv.conf) )
  search_domain=$(awk '/search/ {printf("%s\n", $2); }' /etc/resolv.conf)

  if [ -z $search_domain ] ; then
    search_domain=$CONFIG_DOMAIN
  fi

  out=( $(dialog --backtitle "$title" \
    --visit-items \
    --title "Network Configuration" \
    --form "DNS Client Configuration" 0 0 0 \
    "DNS Server 1 IP" 1 0 "${resolvers[0]}" 1 20 16 0 \
    "DNS Server 2 IP" 2 0 "${resolvers[1]}" 2 20 16 0 \
    "Search Domain" 4 0 "$search_domain" 4 20 24 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  if [ ${#out[@]} -lt 3 ] ; then
    dialog --backtitle "$title" \
      --msgbox "All fields are required" 5 40
    set_resolvers
  fi

  CONFIG_DNS1="${out[0]}"
  CONFIG_DNS2="${out[1]}"
  CONFIG_DNS_SEARCH="${out[2]}"

  __is_ip "$CONFIG_DNS1" || warn \
    "$CONFIG_DNS1 is not a valid IP" "set_resolvers"

  __is_ip "$CONFIG_DNS2" || warn \
    "$CONFIG_DNS2 is not a valid IP" "set_resolvers"

  # TODO validate dns search domain

  # we also set the resolver so that dig can work against
  # whatever nameserver is put into this list
  if [ -f /etc/resolv.conf ] ; then
    mv /etc/resolv.conf /etc/resolv.conf-sdcsetup
  fi

  echo "nameserver $CONFIG_DNS1" > /etc/resolv.conf
  echo "nameserver $CONFIG_DNS2" >> /etc/resolv.conf
  echo "domain $CONFIG_DNS_SEARCH" >> /etc/resolv.conf

  STATUS_DNS_IS_SETUP=0
  callback
}


# NTP client configuration. NTP server is queried using dig and
# if validated / reachable is stored in the config
set_ntp() {
  local out
  local hosts

  set_title "NTP Configuration"

  out=$(dialog --backtitle "$title" \
    --title "NTP Client Configuration" \
    --inputbox "Please specify an NTP Server.\n\
Enter 'localhost' to use the system clock" 0 0 "$CONFIG_NTP_HOST" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  [[ -z $out ]] && out=localhost

  if [ $out == 'localhost' ] ; then
    CONFIG_NTP_HOST="localhost"
    CONFIG_NTP_IPADDR="127.0.0.1"
  else
    hosts=( $(dig +short $out) )

    if [ $? -eq 0 ] ; then
      dialog --backtitle "$title" \
        --title "Syncing with NTP server" \
        --infobox "Attempting to sync with NTP server $out ($hosts)" 4 40

      loginfo $hosts
      ntpdate -d -b $hosts >> $LOG 2>&1

      if [ $? -ne 0 ] ; then
        dialog --backtitle "$title" \
          --title "NTP Configuration Error" \
          --msgbox "Could not reach an NTP server at ${out}" 0 0
        set_ntp
      else
        CONFIG_NTP_HOST="${out}"
        CONFIG_NTP_IPADDR="${hosts[0]}"
        dialog --clear --backtitle "$title" \
          --msgbox "NTP sync successful" 5 23
      fi
    else
      dialog --backtitle "$title" \
        --title "NTP Configuration Error" \
        --msgbox "Could not reach an NTP server at ${out}" 0 0
      set_ntp
    fi
  fi

  STATUS_NTP_IS_SETUP=0
  callback
}

##############################################
# Menus
##############################################

# prints the menu for changing values for a particular service
# right now that's just the IP address
service_setup_generic() {
  set_callback "services_menu"
  set_title "Services ($1)"

  service_key="CONFIG_$1_NET_IPADDR"
  loginfo "setting service: $service_key"

  out=( $(dialog --backtitle "$title" \
    --visit-items \
    --title "IP address ($1)" \
    --cancel-label "Back" \
    --form "Service Configuration ($1)" 0 0 0 \
    "IP Address"       1 0 "${!service_key}"    1 20 16 0 \
    "Network"          2 0 "$CONFIG_NET_IPNET"  2 20  0 0 \
    "Subnet Mask"      3 0 "$CONFIG_NET_IPMASK" 3 20  0 0 \
    "Default Gateway"  4 0 "$CONFIG_NET_IPGW"   4 20  0 0 \
    "VLAN"             5 0 "0 (native)"         5 20  0 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    services_menu
  fi

  __is_ip "${out[0]}" || warn \
    "${out[0]} is not a valid IP" "service_setup $1"

  __is_in_net $CONFIG_NET_IPNET $CONFIG_NET_IPMASK "${out[0]}" || warn \
    "${out[0]} is not in this network" "service_setup $1"

  eval $service_key="${out[0]}"

  services_menu
}


service_setup_dhcp() {
  set_callback "services_menu"
  set_title "Services ($1)"

  service_key="CONFIG_$1_NET_IPADDR"
  loginfo "setting service: $service_key"

  out=( $(dialog --backtitle "$title" \
    --title "IP address ($1)" \
    --cancel-label "Back" \
    --form "Service Configuration ($1)" 0 0 0 \
    "IP Address"       1 0 "${!service_key}"    1 20  16 0 \
    "Network"          2 0 "$CONFIG_NET_IPNET"  2 20   0 0 \
    "Subnet Mask"      3 0 "$CONFIG_NET_IPMASK" 3 20   0 0 \
    "Default Gateway"  4 0 "$CONFIG_NET_IPGW"   4 20   0 0 \
    "VLAN"             5 0 "0 (native)"         5 20   0 0 \
    "DHCP Start"       7 0 "$CONFIG_DHCP_START" 7 20  16 0 \
    "DHCP Stop"        8 0 "$CONFIG_DHCP_STOP " 8 20  16 0 \
    2>&1 1>&3 ) )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    services_menu
  fi

  __is_ip "${out[0]}" || warn \
    "${out[0]} is not a valid IP" "service_setup $1"

  __is_in_net $CONFIG_NET_IPNET $CONFIG_NET_IPMASK "${out[0]}" || warn \
    "${out[0]} is not in this network" "service_setup $1"

  __is_in_net $CONFIG_NET_IPNET $CONFIG_NET_IPMASK "${out[1]}" || warn \
    "DHCP start must belong to network" "service_setup $1"

  __is_in_net $CONFIG_NET_IPNET $CONFIG_NET_IPMASK "${out[2]}" || warn \
    "DHCP stop must belong to network" "service_setup $1"

  eval $service_key="${out[0]}"

  services_menu
}


account_menu() {
  set_callback "account_menu" # return to menu after selection complete
  set_title "Services (expert)"

  out=$(dialog --backtitle "$title" \
    --title "Account Configuration Menu" \
    --visit-items \
    --cancel-label "Back" \
    --menu "Please select one of the users to edit" 0 0 0 \
    "root"  "$(printf "%-22s %8s" "Set root password" "")" \
    "admin" "$(printf "%-22s %8s" "Set admin password" "")" \
    "api"   "$(printf "%-22s %8s" "Set API password" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  case $out in
    root)
      set_password ROOT
      ;;
    admin)
      set_password ADMIN
      ;;
    api)
      set_password API
      ;;
  esac
}


# prints the services menu which is used to configure individual zones
# zones automatically have their configuration populated after the
# initial network configuration is completed
services_menu() {
  set_callback "services_menu" # return to menu after selection complete
  set_title "Services (expert)"

  out=$(dialog --backtitle "$title" \
    --title "Services Configuration Menu" \
    --visit-items \
    --cancel-label "Back" \
    --menu "Please select one of the configuration options" 13 50 4 \
    "assets"   "$(printf "%-22s %8s" "Static Assets Server" "")" \
    "dhcpd"    "$(printf "%-22s %8s" "Management DHCP Daemon" "")" \
    "amqp"     "$(printf "%-22s %8s" "AMQP Message Bus" "")" \
    "mapi"     "$(printf "%-22s %8s" "Master API" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    launch_menu
  fi

  set_last_item $out

  case $out in
    mapi)
      service_setup_generic MAPI
      ;;
    assets)
      service_setup_generic ASSETS
      ;;
    dhcpd)
      service_setup_dhcp DHCP
      ;;
    amqp)
      service_setup_generic AMQP
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
    --visit-items \
    --default-item "$last_menu_item" \
    --menu "Please select one of the configuration options" 18 50 11 \
    "datacenter" "$(printf "%-22s %8s" "Datacenter" "")" \
    "hostname"   "$(printf "%-22s %8s" "Set Hostname" "")" \
    "networks"   "$(printf "%-22s %8s" "Network Configuration" "")" \
    "resolvers"  "$(printf "%-22s %8s" "DNS Resolvers" "")" \
    "ntp"        "$(printf "%-22s %8s" "NTP Client" "")" \
    "keyboard"   "$(printf "%-22s %8s" "Keyboard Layout" "")" \
    "phonehome"  "$(printf "%-22s %8s" "Feedback Support" "")" \
    "accounts"   "$(printf "%-22s %8s" "Users & Accounts" "> ")" \
    "services"   "$(printf "%-22s %8s" "Configure Services" "> ")" \
    "rescue"     "$(printf "%-22s %8s" "Launch Rescue Shell" "")" \
    "apply"      "$(printf "%-22s %8s" "Save & Install" "")" \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_CANCEL ] ; then
    exit 1
  fi

  set_last_item $out

  case $out in
    datacenter)
      setup_datacenter
      ;;
    hostname)
      set_fqdn
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
    accounts)
      account_menu
      ;;
    keyboard)
      setup_kbd
      ;;
    phonehome)
      set_phonehome
      ;;
    services)
      services_menu
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


write_old_config() {
  __wr "#----------------------------------------------------------------"
  __wr "# SDC 7 Headnode Configuration"
  __wr "#----------------------------------------------------------------"
  __wr "# version: 0.1"
  __wr "# date: $(date)"
  __wr "#"
  __wr "# this file was auto-generated and must be source-able by bash."
  __wr "#"
  __is_vmware && __wr "coal=true"
  __wr ""
  __wr "datacenter_name=\"$CONFIG_DCID\""
  __wr "datacenter_company_name=\"$CONFIG_COMPANY\""
  __wr "datacenter_location=\"$CONFIG_CITY, $CONFIG_STATE\""
  __wr "datacenter_headnode_id=0"
  __wr ""
  __wr "default_rack_name=RACK1" #XXX
  __wr "default_rack_size=42"    #XXX
  __wr "default_server_role=pro" #XXX
  __wr "default_package_sizes=\"128,256,512,1024\"" #XXX
  __wr ""
  __wr "mail_to=root@localhost"
  __wr "mail_from=root@localhost"
  __wr ""
  __wr "admin_nic=$CONFIG_NET_MACADDR"
  __wr "admin_ip=$CONFIG_NET_IPADDR"
  __wr "admin_netmask=$CONFIG_NET_IPMASK"
  __wr "admin_network=$CONFIG_NET_IPNET"
  __wr "admin_gateway=$CONFIG_NET_IPGW"
  __wr "dns_resolvers=$CONFIG_DNS1,$CONFIG_DNS2"
  __wr "dns_domain=$CONFIG_DNS_SEARCH"
  __wr ""
  __wr "headnode_default_gateway=$CONFIG_NET_IPGW"
  __wr "compute_node_default_gateway=$CONFIG_NET_IPGW"
  __wr ""
  __wr "root_shadow='$(/usr/lib/cryptpass $CONFIG_PASS_ROOT)'"
  __wr "admin_shadow='$(/usr/lib/cryptpass $CONFIG_PASS_ADMIN)'"
  __wr ""
  __wr "ntp_hosts=$CONFIG_NTP_IPADDR"
  __wr "compute_node_ntp_hosts=$CONFIG_NET_IPADDR"
  __wr ""
  __wr "assets_root_pw=$CONFIG_PASS_ROOT"
  __wr "assets_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "assets_admin_ip=$CONFIG_ASSETS_NET_IPADDR"
  __wr ""
  __wr "dhcpd_root_pw=$CONFIG_PASS_ROOT"
  __wr "dhcpd_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "dhcpd_admin_ip=$CONFIG_DHCP_NET_IPADDR"
  __wr "dhcp_range_start=$CONFIG_DHCP_START"
  __wr "dhcp_range_end=$CONFIG_DHCP_STOP"
  __wr ""
  __wr "rabbitmq_root_pw=$CONFIG_PASS_ROOT"
  __wr "rabbitmq_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "rabbitmq_admin_ip=$CONFIG_AMQP_NET_IPADDR"
  __wr "rabbitmq=guest:guest:$CONFIG_AMQP_NET_IPADDR:5672"
  __wr ""
  __wr "mapi_root_pw=$CONFIG_PASS_ROOT"
  __wr "mapi_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "mapi_admin_ip=$CONFIG_MAPI_NET_IPADDR"
  __wr "mapi_client_url=http://$CONFIG_MAPI_NET_IPADDR:80"
  __wr "mapi_mac_prefix=90b8d0"     # WTF?
  __wr "mapi_http_port=8080"        # again WTF?
  __wr "mapi_http_admin_user=admin" # sigh
  __wr "mapi_http_admin_pw=$CONFIG_PASS_API"
  __wr "mapi_datasets=\"smartos,nodejs\""
  __wr ""
  __wr "phonehome_automatic=$CONFIG_PHONEHOME"
  __wr ""
  __wr "#----------------------------------------------------------------"
  __wr "# Do not edit below this line. These values will be deprecated"
  __wr "#----------------------------------------------------------------"
  __wr ""
  __wr "swap=0.25x"  #XXX
  __wr "compute_node_swap=0.25x" #XXX
  __wr "cloudapi_root_pw=$CONFIG_PASS_ROOT"
  __wr "cloudapi_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "capi_root_pw=$CONFIG_PASS_ROOT"
  __wr "capi_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "billapi_root_pw=$CONFIG_PASS_ROOT"
  __wr "billapi_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "riak_root_pw=$CONFIG_PASS_ROOT"
  __wr "riak_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "portal_root_pw=$CONFIG_PASS_ROOT"
  __wr "portal_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "dnsapi_http_port=8000"
  __wr "dnsapi_root_pw=$CONFIG_PASS_ROOT"
  __wr "dnsapi_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "amon_root_pw=$CONFIG_PASS_ROOT"
  __wr "amon_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "ca_root_pw=$CONFIG_PASS_ROOT"
  __wr "ca_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "adminui_root_pw=$CONFIG_PASS_ROOT"
  __wr "adminui_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "adminui_help_url=http://sdcdoc.joyent.com/"
  __wr "redis_root_pw=$CONFIG_PASS_ROOT"
  __wr "redis_admin_pw=$CONFIG_PASS_ADMIN"
  __wr "dhcp_lease_time=86400"
  __wr "dhcp_next_server=$CONFIG_DHCP_NET_ADDR"
  __wr "ufds_is_local=true"
  __wr "ufds_external_vlan=0"
  __wr "ufds_ldap_root_dn=cn=root"
  __wr "ufds_ldap_root_pw=secret"
  __wr "ufds_admin_login=admin"
  __wr "ufds_admin_email=root@localhost"
  __wr "ufds_admin_uuid=930896af-bf8c-48d4-885c-6573a94b1853"
  __wr "capi_http_admin_user=admin"
  __wr "capi_http_admin_pw=tot@ls3crit"
  __wr "default_rack_name=RACK1"
  __wr "initial_script=scripts/headnode.sh"  # XXX
  __wr ""
  __wr ""
  __wr "# End of config"
}


# dialog for checking & applying configuration
apply_config() {
  local out

  set_title "Apply & Install"
  # checks if setup is complete
  check_setup

  out=$(dialog --backtitle "$title" \
    --yesno "Apply configuration & Install SDC?" 0 0 \
    2>&1 1>&3 )

  if [ $? -eq $DIALOG_OK ] ; then
    write_old_config
    write_config
  else
    launch_menu
  fi

}

# Main
initial_flow() {
  print_welcome
  print_eula
  setup_datacenter
  set_fqdn
  select_networks
  set_resolvers
  set_ntp
  set_password ADMIN
  set_password API
  CONFIG_PASS_ROOT=$CONFIG_PASS_ADMIN
  STATUS_PASS_ROOT_IS_SETUP=0
  set_phonehome
  apply_config
}

#launch_menu
initial_flow
