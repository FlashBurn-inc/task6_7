#!/usr/bin/env bash

	#font
	n=$(tput sgr0);
	bold=$(tput bold);
	
path=$(echo $0 | sed -r 's/vm1.sh/vm1.config/g')
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

echo ${bold}"---Config options---"${n}
echo ${bold}"Path to config:"${n} $(echo $way)

#EXTERNAL_IF
EXTERNAL_IF=$(grep EXTERNAL_IF $way | awk -F= '{print $2}' | sed -r 's/\"//g')
echo ${bold}"EXTERNAL_IF:"${n} $(echo $EXTERNAL_IF)
#INTERNAL_IF
INTERNAL_IF=$(grep INTERNAL_IF $way | awk -F= '{print $2}' | sed 's/\"//g')
echo ${bold}"INTERNAL_IF:"${n} $(echo $INTERNAL_IF)
#MANAGEMENT_IF
MANAGEMENT_IF=$(grep MANAGEMENT_IF $way | awk -F= '{print $2}' | sed 's/\"//g')
echo ${bold}"MANAGEMENT_IF:"${n} $(echo $MANAGEMENT_IF)
#VLAN
VLAN=$(grep VLAN $way | awk -F= 'FNR==1{print $2}')
echo ${bold}"VLAN:"${n} $(echo $VLAN)
#EXT_IP=”DHCP” или пара параметров (EXT_IP=172.16.1.1/24, EXT_GW=172.16.1.254)
EXT_IPch=$(grep EXT_IP $way | awk -F= '{print $2}' | sed 's/\"//g')
if [[ $EXT_IPch != DHCP ]]
        then 
                EXT_IP=$(grep EXT_IP $way | awk -F, '{print $1}' | awk -F= '{print $2}')
                EXT_GW=$(grep EXT_GW $way | awk -F, '{print $2}' | awk -F= '{print $2}')
				if [[ -z $EXT_GW ]]
					then
						EXT_GW=$(grep EXT_GW $way | awk -F= '{print $2}')
				fi
        else 
                EXT_IP=$EXT_IPch
fi
echo ${bold}"EXT_IP:"${n} $(echo $EXT_IP)
echo ${bold}"EXT_GW:"${n} $(echo ${EXT_GW:-You use DHCP})
#INT_IP
INT_IP=$(grep INT_IP $way | awk -F= '{print $2}')
echo ${bold}"INT_IP:"${n} $(echo $INT_IP)
#VLAN_IP
VLAN_IP=$(grep VLAN_IP $way | awk -F= 'FNR==1{print $2}')
echo ${bold}"VLAN_IP:"${n} $(echo $VLAN_IP)
#NGINX_PORT
NGINX_PORT=$(grep NGINX_PORT $way | awk -F= '{print $2}')
echo ${bold}"NGINX_PORT:"${n} $(echo $NGINX_PORT)
#APACHE_VLAN_IP
APACHE_VLAN_IP=$(grep APACHE_VLAN_IP $way | awk -F= '{print $2}')
echo ${bold}"APACHE_VLAN_IP:"${n} $(echo $APACHE_VLAN_IP)

#NETWORK CONFIG
echo  ${bold}"---Network setup---"
ip link set $EXTERNAL_IF up
echo "$EXTERNAL_IF up"
ip link set $INTERNAL_IF up
echo "$INTERNAL_IF up"
ip link set $MANAGEMENT_IF up
echo "$MANAGEMENT_IF up"${n}

#External setup
if [[ $EXT_IP == DHCP ]]
	then
		echo "External interface use DHCP configuration"
	else
		ip addr add $EXT_IP dev $EXTERNAL_IF
		ip route add default via $EXT_GW dev $EXTERNAL_IF
		echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/base
		resolvconf -u
		echo ${bold}"External interface use static configuration:"
		echo "IP $EXT_IP default gateway $EXT_GW"${n}
fi

#Internal setup
ip addr add $INT_IP dev $INTERNAL_IF
echo ${bold}"Internal interface: IP $INT_IP"${n}

#vlan
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
VLAN_IF=$(echo "$INTERNAL_IF"."$VLAN")
ip addr add $VLAN_IP dev $VLAN_IF
ip link set $VLAN_IF up
echo ${bold}"Apache vlan created: tag $VLAN ip $VLAN_IP interface $VLAN_IF"${n}

#ip_forwarding
echo "1" > /proc/sys/net/ipv4/ip_forward
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -A FORWARD -i $INTERNAL_IF -o $EXTERNAL_IF -j ACCEPT
iptables -A FORWARD -i $EXTERNAL_IF -o $INTERNAL_IF -j ACCEPT
#iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE
srcip=$(ip addr show $EXTERNAL_IF | grep inet | awk '{ print $2; }' | sed 's/\/.*$//' | awk 'FNR==1{print $1}')
srcnet=$(ip route | grep $EXTERNAL_IF | awk 'FNR==2{print $1}')
iptables -t nat -A POSTROUTING -s $srcnet -o $EXTERNAL_IF -j MASQUERADE
#ca ssl
openssl genrsa -out /etc/ssl/root-ca.key 4096
openssl req -x509 -newkey rsa:4096 -passout pass:1234 -keyout /etc/ssl/root-ca.key -out /etc/ssl/certs/root-ca.crt -subj "/C=UA/O=VM/CN=vm1ca" 
openssl genrsa -out /etc/ssl/web.key 4096
openssl req -new -key /etc/ssl/web.key -out /etc/ssl/web.csr -subj "/C=UA/O=VM/CN=vm1" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:vm1,DNS:$srcip"))
openssl x509 -req -in /etc/ssl/web.csr -CA /etc/ssl/certs/root-ca.crt -passin pass:1234 -CAkey /etc/ssl/root-ca.key -CAcreateserial -out /etc/ssl/certs/web.crt -days 365 -extfile <(printf "subjectAltName=DNS:vm1,DNS:$srcip")
cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt
echo "$srcip vm1" >> /etc/hosts
echo "vm1" > /etc/hostname
cp /etc/ssl/certs/root-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

#install nginx
apt install -y nginx

echo "server {" > /etc/nginx/sites-available/default 
echo "listen $NGINX_PORT ssl;" >> /etc/nginx/sites-available/default 
echo "ssl on;" >> /etc/nginx/sites-available/default
echo "ssl_certificate /etc/ssl/certs/web.crt;" >> /etc/nginx/sites-available/default
echo "ssl_certificate_key /etc/ssl/web.key;" >> /etc/nginx/sites-available/default
echo "server_name vm1;" >> /etc/nginx/sites-available/default
echo "location / {" >> /etc/nginx/sites-available/default
echo "proxy_pass http://$APACHE_VLAN_IP/;" >> /etc/nginx/sites-available/default
#echo "proxy_set_header   X-Real-IP \$remote_addr;" >> /etc/nginx/sites-available/default
#echo "proxy_set_header   Host \$http_host;" >> /etc/nginx/sites-available/default
#echo "proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default
echo "error_page 497 =444 @close;" >> /etc/nginx/sites-available/default
echo "location @close {" >> /etc/nginx/sites-available/default
echo "return 0;" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default 
echo ${bold}"nginx config:"
cat /etc/nginx/sites-available/default 
echo ${n}""
systemctl restart nginx