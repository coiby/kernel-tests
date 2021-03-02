#! /bin/bash

. ./cki_nf_lib.sh

install_dependence

. iptables.sh

# If disable ipv6, skip test
ping -6 ::1 -c1 -W1
[ $? -eq 2 ] && exit 0

. ip6tables.sh
