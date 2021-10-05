#!/bin/bash

source config.sh
source util.sh

# CMD Line args
if [ "$1" == '' ]; then
	echo "USAGE: ./createQrClient.sh clientName [wginterface OPTIONAL]"
	echo ""
	echo "Already created keys:"
	ls ${CONFKEYDIR} | grep .conf
	exit
fi
if [ "$2" != '' ]; then
	if [ -f "/etc/wireguard/${2}.conf" ]; then
		interface=$2
		echo "Operating on interface $interface"
	fi
fi

if [ ! -d ${CONFKEYDIR} ]; then
	mkdir ${CONFKEYDIR}
fi
if [ ! -d ${CONFKEYDIR}/interfaces ]; then
	mkdir ${CONFKEYDIR}/interfaces
fi

# Main
CLIENTNAME=${1//.conf/}
SRVPUBKEY=`cat publickey`

if [ -f "${CONFKEYDIR}/${CLIENTNAME}.key.pub" ]; then
	echo "Key with such name exists. Not re-generating the key."
else
	read -p "Will create client keys named $1. Continue? [Y/n] " -n 1 -r
        echo    # (optional) move to a new line
        if [[ $REPLY =~ ^[Yy]$ ]]; then
                # do dangerous stuff
                echo "Creating client keys for $0"
        else
                [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
        fi

	wg genkey | sudo tee ${CONFKEYDIR}/${CLIENTNAME}.key | wg pubkey | sudo tee ${CONFKEYDIR}/${CLIENTNAME}.key.pub
fi
PRIVKEY=`cat ${CONFKEYDIR}/${CLIENTNAME}.key`
PUBKEY=`cat ${CONFKEYDIR}/${CLIENTNAME}.key.pub`

# Conf
if [ "$interface" == '' ]; then
	getInterface
fi
ENDPOINTPORT=$(cat /etc/wireguard/${interface}.conf | grep ListenPort | cut -d "=" -f 2 | cut -d "/" -f 1 | tr -d " ")

if [ ! -d ${CONFKEYDIR}/$interface ]; then
	mkdir ${CONFKEYDIR}/$interface
fi

if [ -f "${CONFKEYDIR}/$interface/${CLIENTNAME}.ip" ]; then		# Client already created
	CLIENTIP=$(cat ${CONFKEYDIR}/$interface/${CLIENTNAME}.ip)
	BASEIP=$(echo $CLIENTIP | cut -d "/" -f 1 | tr -d " " | rev | cut -d "." -f2- | rev)
	echo "Peer already set up for interface. Using ip ${CLIENTIP}."
else									# Client is new client
	COUNTER=`cat ${CONFKEYDIR}/${interface}/currentIpCounter.int 2>/dev/null || echo 2`
	BASEIP=$(cat /etc/wireguard/${interface}.conf | grep Address | cut -d "=" -f 2 | cut -d "/" -f 1 | tr -d " " | rev | cut -d "." -f2- | rev)
	CLIENTIP="${BASEIP}.${COUNTER}"
	echo $((COUNTER+1)) > ${CONFKEYDIR}/${interface}/currentIpCounter.int
	echo $CLIENTIP > ${CONFKEYDIR}/$interface/${CLIENTNAME}.ip
fi

# Create config file
sudo tee ${CONFKEYDIR}/${interface}/${CLIENTNAME}.conf > /dev/null <<EOT
[Interface]
PrivateKey = ${PRIVKEY}
Address = ${CLIENTIP}/32
DNS = ${BASEIP}.1

[Peer]
PublicKey = $SRVPUBKEY
AllowedIPs = ${BASEIP}.0/24
Endpoint = ${WANIP}:${ENDPOINTPORT}
PersistentKeepalive = 25
EOT

qrencode -t ansiutf8 < ${CONFKEYDIR}/${interface}/${CLIENTNAME}.conf

echo "Client has pubkey: $PUBKEY and IP $CLIENTIP"

read -p "Authorize now on interface $interface? [Y/n] " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
	echo ""
	echo "Authorizing $CLIENTNAME."

	if [ "$(cat /etc/wireguard/${interface}.conf | grep $PUBKEY)" == '' ]; then
		sudo tee -a /etc/wireguard/${interface}.conf > /dev/null <<EOT

[Peer]
PublicKey = $PUBKEY
AllowedIPs = ${CLIENTIP}/32
EOT
chmod 700 ${CONFKEYDIR}/${interface}/${CLIENTNAME}.conf
	
	fi

	sudo wg set $interface peer $PUBKEY allowed-ips $CLIENTIP/32
	echo "Granted access to $CLIENTNAME on $CLIENTIP"
fi