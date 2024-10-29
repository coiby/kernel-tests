#!/bin/sh
# shellcheck disable=SC2154,SC1083
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

rlPhaseStartSetup "Forward $1"
	if [ "$1x" == "ipv4x" ];then
		family=ip
		rlRun "do_setup ipv4" 0 "ipv4 topo init done..."
	elif [ "$1x" == "ipv6x" ];then
		family=ip6
		rlRun "do_setup ipv6" 0 "ipv6 topo init done..."
	else
		rlFail 'Not specify ipv4/ipv6 in $1'
		exit 1;
	fi

	if [ -n "$INET" ];then
		family=inet
	fi
rlPhaseEnd

rlPhaseStartTest "nftables $family family $1 policy test input/output path"
	run server nft add table ${family} filter
	for chain in prerouting input output postrouting; do
		run server nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; policy accept \\\; }
		run client ping -$(4or6 $ip_s) $ip_s -c1
		run server nft delete chain ${family} filter ${chain}

		run server nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; policy drop \\\; }
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run server nft delete chain ${family} filter ${chain}
	done

	run client ping -$(4or6 $ip_s) $ip_s -c 30 -i 0.2
	run server nft delete table ${family} filter
rlPhaseEnd

	# policy test forward path
rlPhaseStartTest "nftables $family family $1 policy test forward path"
	run router nft add table ${family} filter
	for chain in prerouting forward postrouting; do
		run router nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; policy accept \\\; }
		run client ping -$(4or6 $ip_s) $ip_s -c1
		run router nft delete chain ${family} filter ${chain}

		run router nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; policy drop \\\; }
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run router nft delete chain ${family} filter ${chain}
	done

	run client ping -$(4or6 $ip_s) $ip_s -c 30 -i 0.2
	run router nft delete table ${family} filter
rlPhaseEnd

	# basic action test input/output path
rlPhaseStartTest "nftables $family family $1 basic action test input/output path"
	run server nft add table ${family} filter
	for chain in prerouting input output postrouting; do
		run server nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; }
		if [ ${chain} == "prerouting" ] || [ ${chain} == "input" ]; then
			option="iifname s_r"
		else
			option="oifname s_r"
		fi

		# nft accept
		run server nft add rule ${family} filter ${chain} ${option} counter accept
		run server nft add rule ${family} filter ${chain} ${option} counter drop
		run client ping -$(4or6 $ip_s) $ip_s -c1
		run server nft list ruleset
		run server nft flush table ${family} filter

		# nft drop
		run server nft add rule ${family} filter ${chain} ${option} counter drop
		run server nft add rule ${family} filter ${chain} ${option} counter accept
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run server nft list ruleset
		run server nft flush table ${family} filter

		# nft return
		run server nft add chain ${family} filter test
		run server nft add rule ${family} filter test ${option} counter return
		run server nft add rule ${family} filter test ${option} counter accept
		run server nft add rule ${family} filter ${chain} ${option} counter jump test
		run server nft add rule ${family} filter ${chain} ${option} counter drop
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run server nft list ruleset
		run server nft flush table ${family} filter

		run server nft delete chain ${family} filter ${chain}
	done
	run server nft delete table ${family} filter
rlPhaseEnd


rlPhaseStartTest "nftables $family family $1 basic action test forward path"
	run router nft add table ${family} filter
	for chain in prerouting forward postrouting; do
		run router nft add chain ${family} filter ${chain} { type filter hook ${chain} priority 0 \\\; }
		if [ ${chain} == "prerouting" ]; then
			option="iifname r_c"
		elif [ ${chain} == "postrouting" ]; then
			option="oifname r_s"
		else
			option="iifname r_c oifname r_s"
		fi

		# nft accept
		run router nft add rule ${family} filter ${chain} ${option} counter accept
		run router nft add rule ${family} filter ${chain} ${option} counter drop
		run client ping -$(4or6 $ip_s) $ip_s -c1
		run router nft list ruleset
		run router nft flush table ${family} filter

		# nft drop
		run router nft add rule ${family} filter ${chain} ${option} counter drop
		run router nft add rule ${family} filter ${chain} ${option} counter accept
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run router nft list ruleset
		run router nft flush table ${family} filter

		# nft return
		run router nft add chain ${family} filter test
		run router nft add rule ${family} filter test ${option} counter return
		run router nft add rule ${family} filter test ${option} counter accept
		run router nft add rule ${family} filter ${chain} ${option} counter jump test
		run router nft add rule ${family} filter ${chain} ${option} counter drop
		run client ping -$(4or6 $ip_s) $ip_s -c1 -W 1 assert_fail
		run router nft list ruleset
		run router nft flush table ${family} filter

		run router nft delete chain ${family} filter ${chain}
	done
	run router nft delete table ${family} filter
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "do_clean"
rlPhaseEnd

rlJournalEnd
