#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

# XXX - TODO
# - if $ntp_hosts == "local", configure ntp for no external time source

exec 4>>/var/log/prompt-config.log
echo "=== Starting prompt-config on $(tty) at $(date) ===" >&4
# BASHSTYLED
export PS4='[\D{%FT%TZ}] $(tty): ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
export BASH_XTRACEFD=4
set -o xtrace

PATH=/usr/sbin:/usr/bin
export PATH

# ERRORS (for getanswer's errno)
ENOTFOUND=1
EBADJSON=2
EUNKNOWN=3

# Defaults
mail_to="root@localhost"
ntp_hosts="0.smartos.pool.ntp.org"
dns_resolver1="8.8.8.8"
dns_resolver2="8.8.4.4"

# Globals
declare -a states
declare -a nics
declare -a assigned
declare prmpt_str

nicsup_done=0

sig_doshell()
{
	echo
	echo
	echo "Bringing up a shell.  When you are done in the shell hit ^D to"
	echo "return to the system configuration tool."
	echo

	/usr/bin/bash

	echo
	echo "Resuming the system configuration tool."
	echo
	printf "$prmpt_str"
}

ip_to_num()
{
    IP=$1

    OLDIFS=$IFS
    IFS=.
    set -- $IP
    num_a=$(($1 << 24))
    num_b=$(($2 << 16))
    num_c=$(($3 << 8))
    num_d=$4
    IFS=$OLDIFS

    num=$((num_a + $num_b + $num_c + $num_d))
}

num_to_ip()
{
    NUM=$1

    fld_d=$(($NUM & 255))
    NUM=$(($NUM >> 8))
    fld_c=$(($NUM & 255))
    NUM=$(($NUM >> 8))
    fld_b=$(($NUM & 255))
    NUM=$(($NUM >> 8))
    fld_a=$NUM

    ip_addr="$fld_a.$fld_b.$fld_c.$fld_d"
}

#
# Converts an IP and netmask to their numeric representation.
# Sets the global variables IP_NUM, NET_NUM, NM_NUM and BCAST_ADDR to their
# respective numeric values.
#
ip_netmask_to_network()
{
	ip_to_num $1
	IP_NUM=$num

	ip_to_num $2
	NM_NUM=$num

	NET_NUM=$(($NM_NUM & $IP_NUM))

	ip_to_num "255.255.255.255"
	local bcasthost
	bcasthost=$((~$NM_NUM & $num))
	BCAST_ADDR=$(($NET_NUM + $bcasthost))
}

# Sets two variables, USE_LO and USE_HI, which are the usable IP addrs for the
# largest block of available host addresses on the subnet, based on the two
# addrs the user has chosen for the GW and External Host IP.
# We look at the three ranges (upper, middle, lower) defined by the two addrs.
calc_ext_default_range()
{
	local a1=$1
	local a2=$2

	local lo=
	local hi=
	if [ $a1 -lt $a2 ]; then
		lo=$a1
		hi=$a2
	else
		lo=$a2
		hi=$a1
	fi

	u_start=$(($hi + 1))
	m_start=$(($lo + 1))
	l_start=$(($NET_NUM + 1))

	u_max=$(($BCAST_ADDR - 1))
	m_max=$(($hi - 1))
	l_max=$(($lo - 1))

	up_range=$(($u_max - $u_start))
	mid_range=$(($m_max - $m_start))
	lo_range=$(($l_max - $l_start))

	if [ $up_range -gt $mid_range ]; then
		USE_LO=$u_start
		USE_HI=$u_max
		range=$up_range
	else
		USE_LO=$m_start
		USE_HI=$m_max
		range=$mid_range
	fi

	if [ $range -lt $lo_range ]; then
		USE_LO=$l_start
		USE_HI=$l_max
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
	return 0
}

# Tests if input is an email address
is_email() {
	# BASHSTYLED
	regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.?)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
	ADDRESS=$1

	[[ $ADDRESS =~ $regex ]] && return 0
	return 1
}

is_dns_label() {
	# http://en.wikipedia.org/wiki/Domain_Name_System#Domain_name_syntax
	# Max 63 chars, alphanumeric and hypen, can't start or end with hyphen,
	# can't be *all* numeric.
	if [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] \
	    && ! [[ "$1" =~ -$ ]] \
	    && ! [[ "$1" =~ ^[0-9]+$ ]] \
	    && [[ "${#1}" -le 63 ]]; then
		return 0
	else
		return 1
	fi
}

function is_true_false() {
	if [[ "$1" == "true" || "$1" == "false" ]]; then
		return 0
	else
		return 1
	fi
}

# You can call this like:
#
#  value=$(getanswer "foo")
#  [[ $? == 0 ]] || fatal "no answer for question foo"
#
getanswer()
{
	local key=$1
	local answer=""
	local potential=""

	if [[ -z ${answer_file} ]]; then
		return ${ENOTFOUND}
	fi

	# json does not distingush between an empty string and a key that's not
	# there with the normal output, so we fix that so we can distinguish.
	# BEGIN BASHSTYLED
	answer=$(/usr/bin/cat ${answer_file} \
		| /usr/bin/json -e "if (this['${key}'] === undefined) this['${key}'] = '<<undefined>>';" \
		"${key}" 2>&1)
	# END BASHSTYLED
	if [[ $? != 0 ]]; then
		if [[ -n $(echo "${answer}" | grep "input is not JSON") ]]; then
			return ${EBADJSON}
		else
			return ${EUNKNOWN}
		fi
	fi

	if [[ ${answer} == "<<undefined>>" ]]; then
		return ${ENOTFOUND}
	fi

	echo "${answer}"
	return 0
}

# Optional input
promptopt()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ $? == 0 ]]; then
			if [[ ${val} == "<default>" ]]; then
				val=${def}
			fi
			return
		fi
	fi

	if [ -z "$def" ]; then
		prmpt_str="$1 [press enter for none]: "
	else
		prmpt_str="$1 [$def]: "
	fi
	printf "$prmpt_str"
	read val
	# If def was null and they hit return, we just assign null to val
	[ -z "$val" ] && val="$def"
}

promptval()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
			return
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1: "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		# Forward and back quotes not allowed
		echo $val | nawk '{
		    if (index($0, "\047") != 0)
		        exit 1
		    if (index($0, "`") != 0)
		        exit 1
		}'
		if [ $? != 0 ]; then
			echo "Single quotes are not allowed."
			val=""
			continue
		fi
		[ -n "$val" ] && break
		echo "A value must be provided."
	done
}

prompt_host_ok_val()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1: "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		if [ -n "$val" ]; then
			trap "" SIGINT
			printf "Checking connectivity..."
			ping $val >/dev/null 2>&1
			if [ $? != 0 ]; then
				printf "UNREACHABLE\n"
			else
				printf "OK\n"
			fi
			trap sig_doshell SIGINT
			break
		else
			echo "A value must be provided."
		fi
	done
}

function prompt_hosts_ok_val()
{
	val=""
	local prompt="$1"
	shift
	local def="$1"
	shift
	local keys="$*"

	local key=
	for key in ${keys}; do
		if [[ -n ${key} ]]; then
			val=$(getanswer "${key}")
			if [[ ${val} == "<default>" && -n ${def} ]]; then
				val=${def}
			fi
			if [[ -n "${val}" ]]; then
				break
			fi
		fi
	done

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="${prompt} [$def]: "
		else
			prmpt_str="${prompt}: "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		if [ -n "$val" ]; then
			trap "" SIGINT
			val=$(echo "$val" | sed -e 's/ *//g') # clean space
			local host
			for host in $(echo "$val" | sed -e 's/,/ /g'); do
				printf "Checking ${host} connectivity..."
				ping $host >/dev/null 2>&1
				if [ $? != 0 ]; then
					printf "UNREACHABLE\n"
				else
					printf "OK\n"
				fi
			done
			trap sig_doshell SIGINT
			break
		else
			echo "A value must be provided."
		fi
	done
}

promptdnslabel()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
			is_dns_label "$val" || val=""
		elif [[ -n ${val} ]]; then
			is_dns_label "$val" || val=""
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1: "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		is_dns_label "$val" || val=""
		[ -n "$val" ] && break
		echo "A valid DNS label must be provided" \
		    "('a-zA-Z0-9-', max 63 characters)."
	done
}

function prompttruefalse()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
			is_true_false "$val" || val=""
		elif [[ -n ${val} ]]; then
			is_true_false "$val" || val=""
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1 (true/false): "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		is_true_false "$val" || val=""
		[ -n "$val" ] && break
		echo "Value must be 'true' or 'false'."
	done
}

promptemail()
{
	val=""
	def="$2"
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
			is_email "$val" || val=""
		elif [[ -n ${val} ]]; then
			is_email "$val" || val=""
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1: "
		fi
		printf "$prmpt_str"
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
	key="$3"

	if [[ -n ${key} ]]; then
		val=$(getanswer "${key}")
		if [[ ${val} == "<default>" && -n ${def} ]]; then
			val=${def}
		fi
		if [[ ${val} != "none" ]]; then
			is_net "$val" || val=""
		fi
	fi

	while [ -z "$val" ]; do
		if [ -n "$def" ]; then
			prmpt_str="$1 [$def]: "
		else
			prmpt_str="$1: "
		fi
		printf "$prmpt_str"
		read val
		[ -z "$val" ] && val="$def"
		if [[ ${val} != "none" ]]; then
			is_net "$val" || val=""
		fi
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
    tag=$(echo $1 | cut -d"'" -f2)
    if [[ -n ${tag} ]]; then
        mac=$(getanswer "${tag}_nic")
        if [[ -n ${mac} ]]; then
            for idx in ${!macs[*]}; do
                if [[ ${mac} == ${macs[${idx}]} ]]; then
                    mac_addr="${macs[${idx}]}"
                    val="${macs[${idx}]}"
                    nic_val="${nics[${idx}]}"
                    return
                fi
            done
        fi
    fi

    if [[ $nic_cnt -eq 1 ]]; then
        val="${macs[1]}"
        nic_val=${nics[1]}
        return
    fi

    printnics
    num=0
    while [ /usr/bin/true ]; do
        prmpt_str="Enter the number of the NIC for the $1 interface: "
        printf "$prmpt_str"
        read num
        if ! [[ "$num" =~ ^[0-9]+$ ]] ; then
                echo ""
        elif [ $num -ge 1 -a $num -le $nic_cnt ]; then
                mac_addr="${macs[$num]}"
                assigned[$num]=$1
                nic_val=${nics[$num]}
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
    key="$4"

	if [[ -n ${key} ]]; then
		preset_val=$(getanswer "${key}")
	fi

	trap "" SIGINT
	while [ /usr/bin/true ]; do
		val=""
		while [ -z "$val" ]; do
			if [[ -n ${preset_val} ]]; then
				val=${preset_val}
			else
				if [ -z "$def" ]; then
					printf "%s: " "$1"
				else
					printf "%s [enter to keep existing]: " \
					    "$1"
				fi
				stty -echo
				read val
				stty echo
				echo
			fi
			if [ -n "$val" ]; then
				echo "$val" | nawk '{
				    if (length($0) < 7) exit 1
				    if (match($0, "[a-zA-Z]") == 0) exit 1
				    if (match($0, "[0-9]") == 0) exit 1
				    exit 0
				}'
				if [ $? -ne 0 -a "$2" == "chk" ]; then
					echo "The password must be at least" \
					    "7 characters long and" \
					    "include 1 letter and"
					echo "1 number."
					val=""
					preset_val=""
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
			if [[ -n ${preset_val} ]]; then
				cval=${preset_val}
			else
				printf "%s: " "Confirm password"
				stty -echo
				read cval
				stty echo
				echo
			fi
			[ -n "$cval" ] && break
			echo "A value must be provided."
		done

		[ "$val" == "$cval" ] && break

		echo "The entries do not match, please re-enter."
	done
	trap sig_doshell SIGINT
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

	if [[ $(getanswer "simple_headers") == "true" ]]; then
		echo "> ${subheader}"
		return
	fi

	if [ $cols -gt 80 ] ;then
		newline='\n'
	fi

	clear
	printf " %-40s\n" "Smart Data Center (SDC) Setup"
	printf " %-40s%38s\n" "$subheader" "http://docs.joyent.com/sdc7"
	for i in {1..80} ; do printf "-" ; done && printf "$newline"
}

print_warning()
{
	clear
	printf "WARNING\n"
	for i in {1..80} ; do printf "-" ; done && printf "\n"
	printf "\n$1\n"

	prmpt_str="\nPress [enter] to continue "
	printf "$prmpt_str"
	read continue
}

nicsup() {
	[ $nicsup_done -eq 1 ] && return

	local vlan_opts=""
	ifconfig $admin_iface inet $admin_ip netmask $admin_netmask up

	if [[ -n ${external_nic} ]]; then
		if [ -n "$external_vlan_id" ]; then
			vlan_opts="-v $external_vlan_id"
		fi

		dladm create-vnic -l $external_iface $vlan_opts external0
		ifconfig external0 plumb
		ifconfig external0 inet $external_ip netmask \
		    $external_netmask up
	fi

	if [[ -n ${headnode_default_gateway}
	    && ${headnode_default_gateway} != "none" ]]; then

		route add default $headnode_default_gateway >/dev/null
	fi

	nicsup_done=1
}

nicsdown() {
	ifconfig ${admin_iface} inet down unplumb
	if [[ -n ${external_nic} ]]; then
		ifconfig external0 inet down unplumb
		dladm delete-vnic external0
	fi
}

trap "" SIGINT

while getopts "f:" opt
do
	case "$opt" in
		f)	answer_file=${OPTARG};;
	esac
done

shift $(($OPTIND - 1))

USBMNT=$1

if [[ -n ${answer_file} ]]; then
	if [[ ! -f ${answer_file} ]]; then
		echo "ERROR: answer file '${answer_file}' does not exist!"
		exit 1
	fi
elif [[ -f ${USBMNT}/private/answers.json ]]; then
	answer_file=${USBMNT}/private/answers.json
fi

#
# Get local NIC info
#
nic_cnt=0

while IFS=: read -r link addr ; do
	((nic_cnt++))
	nics[$nic_cnt]=$link
	macs[$nic_cnt]=`echo $addr | sed 's/\\\:/:/g'`
	# reformat the nic so that it's in the proper 00:00:ab... not 0:0:ab...
	macs[$nic_cnt]=$(printf "%02x:%02x:%02x:%02x:%02x:%02x" \
	    $(echo "${macs[${nic_cnt}]}" \
	    | tr ':' ' ' | sed -e "s/\([A-Fa-f0-9]*\)/0x\1/g"))
	assigned[$nic_cnt]="-"
done < <(dladm show-phys -pmo link,address 2>/dev/null)

if [[ $nic_cnt -lt 1 ]]; then
	echo "ERROR: cannot configure the system, no NICs were found."
	exit 0
fi

# Don't do an 'ifconfig -a' - this causes some nics (bnx) to not
# work when combined with the later dladm commands
for iface in $(dladm show-phys -pmo link); do
	ifconfig $iface plumb 2>/dev/null
done
updatenicstates

export TERM=xterm-color
stty erase ^H

trap sig_doshell SIGINT

printheader "Copyright 2014, Joyent, Inc."

message="
Before proceeding with the installation of SDC please familiarise yourself with
the architecture and components of SDC by reviewing the SDC 7 Overview:

http://docs.joyent.com/sdc7/overview-of-smartdatacenter-7.

Please also read through the installation instructions:

http://docs.joyent.com/sdc7/installing-sdc7

paying particular attention to the "Preparation" section and the networking
requirements.

You must answer the following questions to configure the head node. You will
have a chance to review and correct your answers, as well as a chance to edit
the final configuration, before it is applied.

At the prompts, if you type ^C you will be placed into a shell. When you exit
the shell the configuration process will resume from where it was interrupted.

Press [enter] to continue"

if [[ $(getanswer "skip_instructions") != "true" ]]; then
	printf "$message"
fi

console=$(getanswer "config_console")
# If we've asked for automatic configuration, but are not running on the
# primary boot console (as selected in the bootloader menu), then pause at a
# prompt:
if [[ -z ${console} || $(tty) != "/dev/console" ]]; then
	read continue;
fi

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
as help with management of distributed systems.

The datacenter *region* and *name* will be used in DNS names. Typically
the region will be a part of datacenter name, e.g. region_name=us-west,
datacenter_name=us-west-1, but this isn't required.
\n\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	promptval "Enter a company name" "$datacenter_company_name" \
	    "datacenter_company_name"
	datacenter_company_name="$val"

	# BASHSTYLED
	promptdnslabel "Enter a region for this datacenter" \
	    "$region_name" "region_name"
	region_name="$val"

	while [ true ]; do
		key="datacenter_name"
		promptdnslabel "Enter a name for this datacenter" \
		    "$datacenter_name" "${key}"
		if [ "$val" != "ca" ]; then
			datacenter_name="$val"
			break
		fi
		echo "The datacenter name 'ca' is reserved for system use"
		# disable key, since this means bad value in answer file
		key=
	done

	promptval "Enter the City and State for this datacenter" \
	    "$datacenter_location" "datacenter_location"
	datacenter_location="$val"

	printheader "Networking"
	message="
Several applications will be made available on these networks using IP
addresses which are automatically incremented based on the headnode IP.
In order to determine what IP addresses have been assigned to SDC, you can
either review the configuration prior to its application, or you can run
'sdc-netinfo' after the install.

Press [enter] to continue"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
		prmpt_str="\nPress [enter] to continue "
		read continue
	fi

	printheader "Networking - Admin"
	message="
The admin network is used for management traffic and other information that
flows between the Compute Nodes and the Headnode in an SDC cluster. This
network will be used to automatically provision new compute nodes and there are
several application zones which are assigned sequential IP addresses on this
network. It is important that this network be used exclusively for SDC
management. Note that DHCP traffic will be present on this network following
the installation and that this network is connected in VLAN ACCESS mode only.
\n\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	promptnic "'admin'"
	admin_nic="$val"
	admin_iface="$nic_val"

	valid=0
	while [ $valid -ne 1 ]; do
		promptnet "(admin) headnode IP address" "$admin_ip" "admin_ip"
		admin_ip="$val"

		[[ -z "$admin_netmask" ]] && admin_netmask="255.255.255.0"

		promptnet "(admin) headnode netmask" "$admin_netmask" \
		    "admin_netmask"
		admin_netmask="$val"
		ip_netmask_to_network "$admin_ip" "$admin_netmask"
		[ $IP_NUM -ne $BCAST_ADDR ] && valid=1
	done

	if [[ -z "$admin_zone_ip" ]]; then
		ip_netmask_to_network "$admin_ip" "$admin_netmask"
		next_addr=$(($IP_NUM + 1))
		num_to_ip $next_addr
		admin_zone_ip="$ip_addr"
	fi

	promptnet "(admin) Zone's starting IP address" "$admin_zone_ip" \
	    "admin_provisionable_start"
	admin_zone_ip="$val"

	printheader "Networking - External"
	message="
The external network is used by the headnode and its applications to connect to
external networks. That is, it can be used to communicate with either the
Internet, an intranet, or any other WAN. This is optional when your system does
not need access to an external network, or where you want to connect to an
external network later.\n\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	if [[ -z ${setup_external_network} ]]; then
		setup_external_network="Y/n"
	fi
	while [[ ${setup_external_network} != "y" && \
	    ${setup_external_network} != "n" ]]; do
		promptopt "Add external network now?" \
		    "${setup_external_network}" "setup_external_network"
		if [[ ${val} == 'y' || ${val} == 'Y' || ${val} == 'yes' || \
		    ${val} == 'true' || ${val} == 'Y/n' ]]; then
			setup_external_network="y"
		elif [[ ${val} == 'n' || ${val} == 'N' || ${val} == 'no' || \
		    ${val} == 'false' ]]; then
			setup_external_network="n"
		else
			echo "Invalid value, use 'y' for yes, 'n' for no."
		fi
	done

	if [[ ${setup_external_network} == 'y' ]]; then

		promptnic "'external'"
		external_nic="$val"
		external_iface="$nic_val"

		valid=0
		while [ $valid -ne 1 ]; do
			promptnet "(external) headnode IP address" \
			    "$external_ip" "external_ip"
			external_ip="$val"

			[[ -z "$external_netmask" ]] && \
			    external_netmask="255.255.255.0"

			promptnet "(external) headnode netmask" \
			    "$external_netmask" "external_netmask"
			external_netmask="$val"

			ip_netmask_to_network "$external_ip" \
			    "$external_netmask"
			[ $IP_NUM -ne $BCAST_ADDR ] && valid=1
		done

		promptnet "(external) gateway IP address" "$external_gateway" \
		    "external_gateway"
		external_gateway="$val"

		promptopt "(external) VLAN ID" "$external_vlan_id" \
		    "external_vlan_id"
		external_vlan_id="$val"

		if [[ -z "$external_provisionable_start" ]]; then
			ip_netmask_to_network "$external_gateway" \
			    "$external_netmask"
			gw_host_addr=$IP_NUM

			ip_netmask_to_network "$external_ip" "$external_netmask"

			# Get USE_LO and USE_HI values for defaults
			calc_ext_default_range $gw_host_addr $IP_NUM

			next_addr=$USE_LO
			num_to_ip $next_addr
			external_provisionable_start="$ip_addr"
			num_to_ip $USE_HI
			external_provisionable_end="$ip_addr"
		fi

		valid=0
		while [ $valid -ne 1 ]; do
			promptnet "Starting provisionable IP address" \
			    "$external_provisionable_start" \
			    "external_provisionable_start"
			external_provisionable_start="$val"
			ip_netmask_to_network "$external_provisionable_start" \
			    "$external_netmask"
			[ $IP_NUM -ne $BCAST_ADDR ] && valid=1
		done

		valid=0
		while [ $valid -ne 1 ]; do
			promptnet "  Ending provisionable IP address" \
			    "$external_provisionable_end" \
			    "external_provisionable_end"
			external_provisionable_end="$val"
			ip_netmask_to_network "$external_provisionable_end" \
			    "$external_netmask"
			[ $IP_NUM -ne $BCAST_ADDR ] && valid=1
		done
	fi

	printheader "Networking - Continued"
	message=""

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	message="
The default gateway will determine which router will be used to connect to
other networks. This will almost certainly be the router connected to your
'External' network. Use 'none' if you have no gateway.\n\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	# default to external_gateway if that's set, if not, use 'none'
	[[ -z "$headnode_default_gateway" && -n ${external_gateway} ]] && \
	    headnode_default_gateway="$external_gateway"
	[[ -z "$headnode_default_gateway" ]] && \
	    headnode_default_gateway="none"

	promptnet "Enter the default gateway IP" "$headnode_default_gateway" \
	    "headnode_default_gateway"
	headnode_default_gateway="$val"

	# Bring the admin and external nics up now: they need to be for the
	# connectivity checks in the next section
	nicsup

	message="
The DNS servers set here will be used to provide name resolution abilities to
the SDC cluster itself. These will also be default DNS servers for zones
provisioned on the 'external' network.\n\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	prompt_host_ok_val "Enter the Primary DNS server IP" "$dns_resolver1" \
	    "dns_resolver1"
	dns_resolver1="$val"
	prompt_host_ok_val "Enter the Secondary DNS server IP" \
	    "$dns_resolver2" "dns_resolver2"
	dns_resolver2="$val"
	promptval "Enter the headnode domain name" "$domainname" "dns_domain"
	domainname="$val"
	promptval "Default DNS search domain" "$dns_domain" "dns_search"
	dns_domain="$val"

	message="
By default the headnode acts as an NTP server for the admin network. You can
set the headnode to be an NTP client to synchronize to another NTP server.\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	# Support for "ntp_host" (singular) in the answers file is for
	# backward compat. Using the plural "ntp_hosts" is now preferred.
	prompt_hosts_ok_val \
	    "Enter NTP server IP address(es) or hostname(s)" "$ntp_hosts" \
	    "ntp_hosts" "ntp_host"
	ntp_hosts="$val"

	# By default we skip the NTP check because we have multiple
	# NTP servers for a reason. One of them failing shouldn't block
	# headnode setup.
	skip_ntp_check=$(getanswer "skip_ntp_check")
	if [[ -n "${skip_ntp_check}" && ${skip_ntp_check} != "true" ]]; then
		for ntp_host in $(echo "$val" | sed -e 's/,/ /g'); do
			ntpdate -q $ntp_host >/dev/null 2>&1
			[ $? != 0 ] && print_warning \
				"Failure querying NTP host '$ntp_host'"
		done
	fi


	printheader "Account Information"
	message="
There are two primary accounts for managing a Smart Data Center.  These are
'admin', and 'root'. Each account can have a unique password. Most of the
interaction you will have with SDC will be using the 'admin' user, unless
otherwise specified.  In addition, SDC has the ability to send notification
emails to a specific address. Each of these values will be configured below.
\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	promptpw "Enter root password" "nochk" "$root_shadow" "root_password"
	root_shadow="$val"

	promptpw "Enter admin password" "chk" "$zone_admin_pw" "admin_password"
	zone_admin_pw="$val"
        # BASHSTYLED
        escaped_zone_admin_pw="$(echo "$zone_admin_pw" | sed -e "s/'/'\\\\''/g")"

	promptemail "Administrator email goes to" "$mail_to" "mail_to"
	mail_to="$val"

	[[ -z "$mail_from" ]] && mail_from="support@${domainname}"
	promptemail "Support email should appear from" "$mail_from" "mail_from"
	mail_from="$val"


	printheader "Telemetry"
	message="
Share usage, health, and hardware data about your data center with
Joyent to help us make SmartDataCenter better.
\n"

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	prompttruefalse "Enable telemetry" "false" "phonehome_automatic"
	phonehome_automatic="$val"


	printheader "Verify Configuration"
	message=""

	if [[ $(getanswer "skip_instructions") != "true" ]]; then
		printf "$message"
	fi

	if [[ $(getanswer "skip_final_summary") != "true" ]]; then
		printf "Company name: $datacenter_company_name\n"
		printf "Datacenter Region: %s, Name: %s, Location: %s\n" \
		    "$region_name" "$datacenter_name" "$datacenter_location"
		printf "Email Admin Address: %s, From: %s\n" \
		    "$mail_to" "$mail_from"
		printf "Domain name: %s, Gateway IP address: %s\n" \
		    $domainname $headnode_default_gateway
		if [[ -n ${external_nic} ]]; then
			if [ -z "$external_vlan_id" ]; then
				ext_vlanid="none"
			else
				ext_vlanid="$external_vlan_id"
			fi
		fi
		printf "%8s %17s %15s %15s %15s %4s\n" "Net" "MAC" \
		    "IP addr." "Netmask" "Gateway" "VLAN"
		printf "%8s %17s %15s %15s %15s %4s\n" "Admin" $admin_nic \
		    $admin_ip $admin_netmask "none" "none"
		if [[ -n ${external_nic} ]]; then
			printf "%8s %17s %15s %15s %15s %4s\n" "External" \
			    $external_nic $external_ip $external_netmask \
			    $external_gateway $ext_vlanid
		fi
		echo
		printf "Admin net zone IP addresses start at: %s\n" \
		    $admin_zone_ip
		if [[ -n ${external_nic} ]]; then
			printf "Provisionable IP range: %s - %s\n" \
			    $external_provisionable_start\
			    $external_provisionable_end
		fi
		printf "DNS Servers: (%s, %s), Search Domain: %s\n" \
		    "$dns_resolver1" "$dns_resolver2" "$dns_domain"
		printf "NTP servers: $ntp_hosts\n"
		echo
		printf "Enable telemetry: $phonehome_automatic\n"
		echo
	fi

	if [[ $(getanswer "skip_final_confirm") != "true" ]]; then
		promptval "Is this correct?" "y"
		[ "$val" == "y" ] && break
		clear
	else
		break
	fi
done

#
# Calculate admin and external network
#
ip_netmask_to_network "$admin_ip" "$admin_netmask"
num_to_ip $NET_NUM
admin_network="$ip_addr"

#
# Calculate admin network IP address for each core zone
#
ip_netmask_to_network "$admin_zone_ip" "$admin_netmask"
next_addr=$IP_NUM
num_to_ip $next_addr
assets_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
dhcpd_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
napi_admin_ip="$ip_addr"
napi_client_url="http://${napi_admin_ip}:80"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
binder_admin_ip="$ip_addr"

# we reserve four more (thus five total) ips for resolvers
binder_resolver_ips="$binder_admin_ip"
for i in {0..3}; do
	next_addr=$(($next_addr + 1))
	num_to_ip $next_addr
	binder_resolver_ips="$binder_resolver_ips,$ip_addr"
done

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
manatee_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
moray_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
ufds_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
workflow_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
rabbitmq_admin_ip="$ip_addr"
rabbitmq="guest:guest:${rabbitmq_admin_ip}:5672"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
imgapi_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
cnapi_admin_ip="$ip_addr"
cnapi_client_url="http://${cnapi_admin_ip}:80"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
amonredis_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
amon_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
fwapi_admin_ip="$ip_addr"
fwapi_client_url="http://${fwapi_admin_ip}:80"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
vmapi_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
sdc_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
papi_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
ca_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
adminui_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
sapi_admin_ip="$ip_addr"

next_addr=$(($next_addr + 1))
num_to_ip $next_addr
mahi_admin_ip="$ip_addr"

# Add 5 to leave some room
next_addr=$(($next_addr + 5))
num_to_ip $next_addr
dhcp_range_start="$ip_addr"

dhcp_range_end=$(getanswer "dhcp_range_end")
if [[ -z "${dhcp_range_end}" || ${dhcp_range_end} == "<default>" ]]; then
	next_addr=$(($BCAST_ADDR - 1))
	num_to_ip $next_addr
	dhcp_range_end="$ip_addr"
fi

#
# Calculate external network
#
if [[ -n ${external_nic} ]]; then
	ip_netmask_to_network "$external_ip" "$external_netmask"
	num_to_ip $NET_NUM
	external_network="$ip_addr"
fi

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

echo "binder_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "binder_admin_ips=$binder_admin_ip" >>$tmp_config
echo >>$tmp_config

echo "manatee_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "manatee_admin_ips=$manatee_admin_ip" >>$tmp_config
echo >>$tmp_config

echo "moray_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "moray_admin_ips=$moray_admin_ip" >>$tmp_config
echo "moray_domain=moray.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "ufds_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "ufds_admin_ips=$ufds_admin_ip" >>$tmp_config
echo "ufds_domain=ufds.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "workflow_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "workflow_admin_ips=$workflow_admin_ip" >>$tmp_config
echo "workflow_domain=workflow.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "imgapi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "imgapi_admin_ips=$imgapi_admin_ip" >>$tmp_config
echo "imgapi_domain=imgapi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "cnapi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "cnapi_admin_ips=$cnapi_admin_ip" >>$tmp_config
echo "cnapi_domain=cnapi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "fwapi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "fwapi_admin_ips=$fwapi_admin_ip" >>$tmp_config
echo "fwapi_domain=fwapi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "vmapi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "vmapi_admin_ips=$vmapi_admin_ip" >>$tmp_config
echo "vmapi_domain=vmapi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "sdc_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "sdc_admin_ips=$sdc_admin_ip" >>$tmp_config
echo "sdc_domain=sdc.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "papi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "papi_admin_ips=$papi_admin_ip" >>$tmp_config
echo "papi_domain=papi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "ca_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "ca_admin_ips=$ca_admin_ip" >>$tmp_config
echo "ca_domain=ca.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "adminui_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "adminui_admin_ips=$adminui_admin_ip" >>$tmp_config
echo "adminui_domain=adminui.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "mahi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "mahi_admin_ips=$mahi_admin_ip" >>$tmp_config
echo "mahi_domain=mahi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "# multiple datacenters exist within one region" >>$tmp_config
echo "region_name=\"$region_name\"" >>$tmp_config

echo "# datacenter_name should be unique in your cloud" >>$tmp_config
echo "datacenter_name=\"$datacenter_name\"" >>$tmp_config
echo "datacenter_company_name=\"$datacenter_company_name\"" >>$tmp_config
echo "datacenter_location=\"$datacenter_location\"" >>$tmp_config
echo >>$tmp_config

echo "default_rack_name=RACK1" >>$tmp_config
echo "default_rack_size=30" >>$tmp_config
echo "default_server_role=pro" >>$tmp_config
echo "default_package_sizes=\"128,256,512,1024\"" >>$tmp_config
echo >>$tmp_config

# BASHSTYLED
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
echo >>$tmp_config

if [[ -n ${external_nic} ]]; then
	# BASHSTYLED
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
	echo "external_provisionable_start=$external_provisionable_start" \
	    >>$tmp_config
	echo "external_provisionable_end=$external_provisionable_end" \
	    >>$tmp_config
	echo >>$tmp_config
fi

if [[ ${headnode_default_gateway} != "none" ]]; then
	echo "headnode_default_gateway=$headnode_default_gateway" >>$tmp_config
fi

echo >>$tmp_config

echo "# Reserved IPs for binder instances" >>$tmp_config
echo "binder_resolver_ips=$binder_resolver_ips" >>$tmp_config
echo >>$tmp_config

echo "dns_resolvers=$dns_resolver1,$dns_resolver2" >>$tmp_config
echo "dns_domain=$dns_domain" >>$tmp_config
echo >>$tmp_config

echo "# These are the dhcp settings for compute nodes on the admin network"\
    >>$tmp_config
echo "dhcp_range_start=$dhcp_range_start" >>$tmp_config
echo "dhcp_range_end=$dhcp_range_end" >>$tmp_config
echo "dhcp_lease_time=2592000" >>$tmp_config
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

if [[ -n ${external_nic} ]]; then
	if [ -z "$external_vlan_id" ]; then
		echo "# adminui_external_vlan=0" >>$tmp_config
	else
		echo "adminui_external_vlan=$external_vlan_id" >>$tmp_config
	fi
fi
# BASHSTYLED
echo "adminui_help_url=http://wiki.joyent.com/display/sdc/Overview+of+SmartDataCenter" >>$tmp_config
echo >>$tmp_config

echo "amon_admin_ips=$amon_admin_ip" >>$tmp_config
echo "amon_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "amon_domain=amon.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "amonredis_admin_ips=$amonredis_admin_ip" >>$tmp_config
echo "amonredis_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "amonredis_domain=amonredis.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

# NOTE: we add admin_ip and admin_ips here because some stuff is hardcoded to
#       use admin_ip.  When this is cleaned up we can just keep ips.
echo "assets_admin_ip=$assets_admin_ip" >>$tmp_config
echo "assets_admin_ips=$assets_admin_ip" >>$tmp_config
echo "assets_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo >>$tmp_config

# NOTE: we add admin_ip and admin_ips here because some stuff is hardcoded to
#       use admin_ip.  When this is cleaned up we can just keep ips.
echo "dhcpd_admin_ip=$dhcpd_admin_ip" >>$tmp_config
echo "dhcpd_admin_ips=$dhcpd_admin_ip" >>$tmp_config
echo "dhcpd_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "dhcpd_domain=dhcpd.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "dsapi_url=https://datasets.joyent.com" >>$tmp_config
echo "dsapi_http_user=honeybadger" >>$tmp_config
echo "dsapi_http_pass=IEatSnakes4Fun" >>$tmp_config
echo >>$tmp_config

if [[ -n ${external_nic} ]]; then
	if [ -z "$external_vlan_id" ]; then
		echo "# cloudapi_external_vlan=0" >>$tmp_config
	else
		echo "cloudapi_external_vlan=$external_vlan_id" >>$tmp_config
	fi
fi
echo "cloudapi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo >>$tmp_config

# NOTE: we add admin_ip and admin_ips here because some stuff is hardcoded to
#       use admin_ip.  When this is cleaned up we can just keep ips.
echo "rabbitmq_admin_ip=$rabbitmq_admin_ip" >>$tmp_config
echo "rabbitmq_admin_ips=$rabbitmq_admin_ip" >>$tmp_config
echo "rabbitmq_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "rabbitmq=$rabbitmq" >>$tmp_config
echo "rabbitmq_domain=rabbitmq.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "ufds_is_master=true" >>$tmp_config
echo "ufds_ldap_root_dn=cn=root" >>$tmp_config
echo "ufds_ldap_root_pw=secret" >>$tmp_config
echo "ufds_admin_login=admin" >>$tmp_config
echo "ufds_admin_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "ufds_admin_email=$mail_to" >>$tmp_config
echo "ufds_admin_uuid=930896af-bf8c-48d4-885c-6573a94b1853" >>$tmp_config
echo "# Legacy CAPI parameters" >>$tmp_config
# Do not remove. Required to work by smart-login.git agent:
echo "# Required by SmartLogin:" >>$tmp_config
echo "capi_client_url=http://$ufds_admin_ip:8080" >>$tmp_config
echo >>$tmp_config

echo "cnapi_client_url=$cnapi_client_url" >>$tmp_config
echo >>$tmp_config

echo "fwapi_client_url=$fwapi_client_url" >>$tmp_config
echo >>$tmp_config

echo "napi_root_pw='$escaped_zone_admin_pw'" >>$tmp_config
echo "napi_admin_ips=$napi_admin_ip" >>$tmp_config
echo "napi_client_url=$napi_client_url" >>$tmp_config
echo "napi_mac_prefix=90b8d0" >>$tmp_config
echo "napi_domain=napi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "sapi_admin_ips=$sapi_admin_ip" >>$tmp_config
echo "sapi_domain=sapi.${datacenter_name}.${dns_domain}" >>$tmp_config
echo >>$tmp_config

echo "phonehome_automatic=${phonehome_automatic}" >>$tmp_config

# Always show the timers and make setup serial for now.
echo "show_setup_timers=true" >> $tmp_config
if [[ $(getanswer "dtrace_zone_setup") == "true" ]]; then
	echo "dtrace_zone_setup=true" >> $tmp_config
fi

echo "" >> $tmp_config

echo
trap "" SIGINT
if [[ $(getanswer "skip_edit_config") != "true" ]]; then
	echo "Your configuration is about to be applied."
	promptval "Would you like to edit the final configuration file?" "n"
	[ "$val" == "y" ] && vi $tmp_config
	clear
fi

echo "The headnode will now finish configuration and reboot. Please wait..."
mv $tmp_config $USBMNT/config
nicsdown
