#!/bin/bash

manual_configuration=false
interface=""
ip_address=""
cidr=""
gateway=""
dns=""

usage() {
	echo "USAGE: $0 [options]"
	echo
	echo "Options:"
	echo "	-m		: manual configuration (static IP). DHCP is used by default."
	echo "	-i INTERFACE	: specify a network interface"
	echo "	-a IP_ADDRESS	: static IP"
	echo "	-c CIDR		: netmask CIDR"
	echo "	-g GATEWAY	: gateway IP"
	echo "	-d DNS		: DNS server IP"
	echo "	-h, --help 	: show this help message"
	exit 0
}

is_valid_ip() {
	local ip=$1
	if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        	return 1
    	fi

	IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
	for octet in $o1 $o2 $o3 $o4; do
		if (( octet < 0 || octet > 255 )); then
			return 1
		fi
	done

	return 0
}

if [[ "$1" == "--help" ]]; then
	usage
fi

while getopts "hmi:a:c:g:d:" opt; do
	case $opt in
		h) usage ;;
		m) manual_configuration=true ;;
		i) interface="$OPTARG" ;;
		a) ip_address="$OPTARG" ;;
		c) cidr="$OPTARG" ;;
		g) gateway="$OPTARG" ;;
		d) dns="$OPTARG" ;;
		\?) exit 1 ;;
	esac
done

if [[ -z "$interface" ]]; then
	echo "Error: no network interface specified with -i."
	exit 1
fi

if [[ ! -d "/sys/class/net/$interface" ]]; then
	echo "Error: this network interface doesn't exist on this computer."
	exit 1
fi

connection_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$interface" | cut -d':' -f1)
if [[ -z "$connection_name" ]]; then
	connection_name="$interface-conn"
	nmcli con add type ethernet ifname "$interface" con-name "$connection_name"
fi

if ! $manual_configuration; then
	echo "Starting DHCP configuration on interface $interface."
	nmcli con down "$connection_name"
	sudo ip addr flush dev "$interface"
	nmcli con mod "$connection_name" ipv4.method auto
	nmcli con up "$connection_name"
	echo "DHCP configuration applied."
	exit 0
fi

if [[ -z "$ip_address" || -z "$cidr" || -z "$gateway" || -z "$dns" ]]; then
	echo "Error: for a manual configuration, specify:"
	echo "	A static IP address with -a."
	echo "	A netmask CIDR with -c."
	echo "	A gateway with -g."
	echo "	A DNS server with -d."
	exit 1
fi

if (( cidr < 1 || cidr > 32 )); then
	echo "Error: CIDR is illegal."
	exit 1
fi

if ! is_valid_ip "$ip_address" || ! is_valid_ip "$gateway" || ! is_valid_ip "$dns"; then
	echo "Error: IP address is illegal."
	exit 1
fi

echo "Static network configuration on $interface..."
nmcli con mod "$connection_name" ipv4.addresses "$ip_address/$cidr"
nmcli con mod "$connection_name" ipv4.gateway "$gateway"
nmcli con mod "$connection_name" ipv4.method manual
nmcli con mod "$connection_name" ipv4.dns "$dns"
nmcli con up "$connection_name"

echo "Network configuration successfull."
