#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# assert_fail: expect command return none 0 value
# NoCheck: Don't check result, expect 0-255
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

rlJournalStart
rlPhaseStartSetup "Forward ipv4"
	rlRun "do_setup ipv4" 0 "ipv4 topo init done..."
rlPhaseEnd

rlPhaseStartTest "iptables: Basic TARGETS"
# Test on server side
for table in filter mangle raw security; do
	for chain in PREROUTING INPUT OUTPUT POSTROUTING; do
		[ $table == "filter" ] && [ $chain == "PREROUTING" ] && continue
		[ $table == "filter" ] && [ $chain == "POSTROUTING" ] && continue
		[ $table == "raw" ] && [ $chain == "INPUT" ] && continue
		[ $table == "raw" ] && [ $chain == "POSTROUTING" ] && continue
		[ $table == "security" ] && [ $chain == "PREROUTING" ] && continue
		[ $table == "security" ] && [ $chain == "POSTROUTING" ] && continue

		if [ $chain == "PREROUTING" ] || [ $chain == "INPUT" ]; then
			cont="-i s_r -s $ip_c -d $ip_s"
		else
			cont="-o s_r -s $ip_s -d $ip_c"
		fi

		# -j ACCEPT
		run server iptables -t $table -A $chain $cont -j ACCEPT
		run server iptables -t $table -A $chain $cont -j DROP
		run client ping -W 1 $ip_s -c1
		run server iptables -t $table -L -n -v
		run server iptables -t $table -F

		# -j DROP
		run server iptables -t $table -A $chain $cont -j DROP
		run server iptables -t $table -A $chain $cont -j ACCEPT
		run client ping -W 1 $ip_s -c1 assert_fail
		run server iptables -t $table -L -n -v
		run server iptables -t $table -F

		# -j RETURN
		run server iptables -t $table -N TEST
		run server iptables -t $table -A TEST $cont -j RETURN
		run server iptables -t $table -A TEST $cont -j DROP
		run server iptables -t $table -A $chain $cont -j TEST
		run server iptables -t $table -A $chain $cont -j ACCEPT
		run client ping -W 1 $ip_s -c1
		run server iptables -t $table -L -n -v
		run server iptables -t $table -F
		run server iptables -t $table -X
	done
done

# Test on router
for table in filter mangle raw security; do
	for chain in PREROUTING FORWARD POSTROUTING; do
		[ $table == "filter" ] && [ $chain == "PREROUTING" ] && continue
		[ $table == "filter" ] && [ $chain == "POSTROUTING" ] && continue
		[ $table == "nat" ] && [ $chain == "FORWARD" ] && continue
		[ $table == "raw" ] && [ $chain == "FORWARD" ] && continue
		[ $table == "raw" ] && [ $chain == "POSTROUTING" ] && continue
		[ $table == "security" ] && [ $chain == "PREROUTING" ] && continue
		[ $table == "security" ] && [ $chain == "POSTROUTING" ] && continue

		if [ $chain == "PREROUTING" ]; then
			cont="-i r_c -s $ip_c -d $ip_s"
		elif [ $chain == "POSTROUTING" ]; then
			cont="-o r_s -s $ip_c -d $ip_s"
		else
			cont="-i r_c -o r_s -s $ip_c -d $ip_s"
		fi

		# -j ACCEPT
		run router iptables -t $table -A $chain $cont -j ACCEPT
		run router iptables -t $table -A $chain $cont -j DROP
		run client ping -W 1 $ip_s -c1
		run router iptables -t $table -L -n -v
		run router iptables -t $table -F

		# -j DROP
		run router iptables -t $table -A $chain $cont -j DROP
		run router iptables -t $table -A $chain $cont -j ACCEPT
		run client ping -W 1 $ip_s -c1 assert_fail
		run router iptables -t $table -L -n -v
		run router iptables -t $table -F

		# -j RETURN
		run router iptables -t $table -N TEST
		run router iptables -t $table -A TEST $cont -j RETURN
		run router iptables -t $table -A TEST $cont -j DROP
		run router iptables -t $table -A $chain $cont -j TEST
		run router iptables -t $table -A $chain $cont -j ACCEPT
		run client ping -W 1 $ip_s -c1
		run router iptables -t $table -L -n -v
		run router iptables -t $table -F
		run router iptables -t $table -X
	done
done
rlPhaseEnd

rlPhaseStartTest "iptables: Plain NAT test"
	SCTP=false
	#DNAT:
	run server "modprobe sctp && SCTP=true" NoCheck
	run server sleep 1
	run router iptables -t nat -A PREROUTING -i r_c -p tcp -j DNAT --to-destination $ip_s:9999
	run router iptables -t nat -A PREROUTING -i r_c -p udp -j DNAT --to-destination $ip_s:9999
	run server ncat -4 -l 9999 NoCheck &
	run server ncat -4 -u -l 9999 NoCheck &
	run router tcpdump -nni r_s -w dnat.pcap NoCheck &
	run server sleep 3
	# DNAT tcp assert pass
	run client ncat -4 $ip_rc 8888 <<<'abc'
	# DNAT udp assert pass
	run client ncat -4 -u $ip_rc 8888 <<<'abc'
	run router conntrack -L $__NoCheck
	if [[ "$SCTP" == "true" && `which sctp_test` ]];then
		run router iptables -t nat -A PREROUTING -i r_c -p sctp -j DNAT --to-destination $ip_s:9999
		run server sctp_test -H 0 -P 9999 -l NoCheck &
		run server sleep 3
		# DNAT sctp assert pass
		run client timeout 5 sctp_test -H $ip_c -P 6013 -h $ip_rc -p 8888 -s -c 1 -x 1 -X 1
		run client sleep 2
		run client pkill -9 sctp_test NoCheck
	fi

	run router conntrack -L $__NoCheck
	run router conntrack -F $__NoCheck
	run router sleep 2

	run router pkill tcpdump
	run router sleep 1
	tcpdump -nnr dnat.pcap
	rlFileSubmit dnat.pcap

	run router iptables -tnat -nvL
	run router iptables -tnat -F
	pkill ncat

	#SNAT
	run router iptables -t nat -A POSTROUTING -o r_s -p tcp -j SNAT --to-source $ip_rs:1234
	run router iptables -t nat -A POSTROUTING -o r_s -p udp -j SNAT --to-source $ip_rs:1234
	run server iptables -A INPUT -i s_r -p tcp ! --sport 1234 -j DROP
	run server iptables -A INPUT -i s_r -p udp ! --sport 1234 -j DROP

	run server ncat -4 -l 9999 NoCheck &
	run server ncat -4 -u -l 9999 NoCheck &
	run router tcpdump -nni r_s -w snat.pcap &
	run server sleep 3
	# SNAT tcp assert pass
	run client ncat -4 $ip_s 9999 <<<'abc'
	# SNAT udp assert pass
	run client ncat -4 -u $ip_s 9999 <<<'abc'
	run router conntrack -L $__NoCheck
	if [[ "$SCTP" == "true" && `which sctp_test` ]];then
		#When snat ip&port, new connection have to wait old conntrack item timeout/disappear
		run router iptables -t nat -A POSTROUTING -o r_s -p sctp -j SNAT --to-source $ip_rs:1234
		run server iptables -A INPUT -i s_r -p sctp ! --sport 1234 -j DROP
		run server sctp_test -H 0 -P 9999 -l NoCheck &
		run server sleep 3
		# SNAT sctp assert_pass
		run client timeout 5 sctp_test -H $ip_c -P 6013 -h $ip_s -p 9999 -s -c 1 -x 1 -X 1
		run client sleep 2
		run client pkill -9 sctp_test NoCheck
	fi

	run router conntrack -L $__NoCheck
	run router conntrack -F $__NoCheck
	run router sleep 2
	pkill tcpdump

	run router sleep 1
	tcpdump -nnr snat.pcap
	rlFileSubmit snat.pcap

	run router iptables -tnat -nvL
	run router iptables -F
	run server iptables -nvL
	run server iptables -F
	pkill ncat
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "do_clean"
rlPhaseEnd

rlJournalEnd
