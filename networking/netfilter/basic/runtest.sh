#! /bin/bash

. ./cki_nf_lib.sh
install_dependence

if which iptables;then
	. iptables.sh

	# If disable ipv6, skip test
	ping -6 ::1 -c1 -W1
	if [ $? -eq 0 ];then
		. ip6tables.sh
	fi
fi

if which nft;then
	. nftables.sh ipv4
	INET=1 . nftables.sh ipv4

	ping -6 ::1 -c1 -W1
	if [ $? -eq 0 ];then
		. nftables.sh ipv6
		INET=1 . nftables.sh ipv6
	fi
fi
