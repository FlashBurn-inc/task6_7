#!/usr/bin/env bash

	#font
	n=$(tput sgr0);
	bold=$(tput bold);
	
path=$(echo $0 | sed -r 's/vm2.sh/vm2.config/g')
        if [[ $path != /* && $path != .* ]];
        then
                way=$(echo "$PWD/$path")
        elif [[ $path == .* ]]
        then
                z=$(echo "$path" | sed 's/.\///')
                way=$(echo "$PWD/$z")
        else
                way=${path:-"$PWD"/}
        fi

source $way

echo ${bold}"---Config options---"${n}
echo ${bold}"Path to config:"${n} $(echo $way)

echo ${bold}"INTERNAL_IF:"${n} $(echo $INTERNAL_IF)
echo ${bold}"MANAGEMENT_IF:"${n} $(echo $MANAGEMENT_IF)
echo ${bold}"VLAN:"${n} $(echo $VLAN)
echo ${bold}"INT_IP:"${n} $(echo $INT_IP)
echo ${bold}"GW_IP:"${n} $(echo $GW_IP)
echo ${bold}"APACHE_VLAN_IP:"${n} $(echo $APACHE_VLAN_IP)

#NETWORK CONFIG
echo ${bold}"---Network setup---"${n}
ip link set $INTERNAL_IF up
echo "$INTERNAL_IF up"
ip link set $MANAGEMENT_IF up
echo "$MANAGEMENT_IF up"

#int conf
ip addr add $INT_IP dev $INTERNAL_IF
ip route add default via $GW_IP dev $INTERNAL_IF
echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/base
resolvconf -u
echo "IP $INT_IP default gateway $GW_IP"

#vlan
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
VLAN_IF=$(echo "$INTERNAL_IF"."$VLAN")
ip addr add $APACHE_VLAN_IP dev $VLAN_IF
ip link set $VLAN_IF up
echo "Apache vlan created: tag $VLAN ip $VLAN_IP interface $VLAN_IF"
hostap=$(echo "$APACHE_VLAN_IP" | sed 's/\/.*$//g')
echo "$hostap vm2" >> /etc/hosts
echo "vm2" > /etc/hostname

apt install -y apache2
echo "Listen $hostap:80" > "/etc/apache2/ports.conf"
systemctl restart apache2
