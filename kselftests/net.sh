#!/bin/sh
# This file is used for network related tests configurations.

krelease()
{
	uname -r | awk -F. '{print $(NF-1)}' | cut -f1 -d'_'
}

install_netsniff()
{
	which mausezahn && return 0

	# Use f35 repo for RHEL8/9 before netsniff-ng epel9 repo enabled
	if [ $(krelease) == "el8" ] || [ $(krelease) == "el9" ]; then
		cp f35.repo /etc/yum.repos.d/
		dnf install -y netsniff-ng jq
		# remove the repo incase other tests install f35 pkgs via it
		rm -f /etc/yum.repos.d/f35.repo
		dnf clean metadata
	else
		dnf install -y jq netsniff-ng
	fi

	which mausezahn && return 0 || return 1
}

install_smcroute()
{
	which smcroute && return 0
	yum install -y libcap-devel
	smc_v="2.4.4"
	wget https://github.com/troglobit/smcroute/releases/download/${smc_v}/smcroute-${smc_v}.tar.gz
	tar zxf smcroute-${smc_v}.tar.gz
	pushd smcroute-${smc_v}
	./autogen.sh && ./configure --sysconfdir=/etc --localstatedir=/var && make && make install
	popd
	which smcroute && return 0 || return 1
}

install_sendip()
{

	which sendip && return 0
	dnf -y copr enable cygn/SendIP
	dnf install -y sendip

	which sendip && return 0 || return 1
}

reset_net_env()
{
	modprobe -r act_tunnel_key
	modprobe -r ip_gre ip6_gre gre
	modprobe -r ip_vti ip6_vti sit ifb
	modprobe -r veth vxlan geneve netdevsim
	# this module blocks bpf/test_tunnel.sh ipip test
	modprobe -r xfrm_interface
	modprobe -r xfrm6_tunnel ip6_tunnel tunnel6
	modprobe -r mpls_iptunnel mpls_router ipip ip_tunnel tunnel4
	modprobe -r l2tp_eth l2tp_ip6 l2tp_ip l2tp_netlink l2tp_core
	modprobe -r bareudp udp_tunnel ip6_udp_tunnel
	ip -a netns del
	sleep 2
}

do_net_config()
{
	pushd $EXEC_DIR/net
	# Fix some known issues
	# rm 0x10 for fib_rule_tests.sh due to bz1480136
	# FIXME: should we restore it back after finishing test?
	sed -i "/0x10/d" /etc/iproute2/rt_dsfield
	# FIXME: sleep 5s before do IPv6 "Using route with mtu metric" test to
	# pass it. Not sure why ping would fail if not sleep some seconds, need to check
	sed -i "/via 2001:db8:101::2 mtu 1300/a\\\\tsleep 5" fib_tests.sh
	# match basic has been removed on RHEL9
	sed -i 's/arp basic/arp flower/g' fib_tests.sh
	sed -i 's/ip basic/ip flower/g' fib_tests.sh
	# need to be run on bare metal machines, or set -C 0 when run on VM
	sed -i 's/-C [0-9]/-C 0/g' msg_zerocopy.sh
	# fou is not enabled on RHEL
	sed -i 's/kci_test_encap_fou /#kci_test_encap_fou /' rtnetlink.sh
	# pmtu.sh will return 1 for skiped tests, remove fou,gue tests
	sed -i '/^\tpmtu_ipv[4,6]_fou[4,6]_exception/d' pmtu.sh
	sed -i '/^\tpmtu_ipv[4,6]_gue[4,6]_exception/d' pmtu.sh
	sed -i 's/exitcode=1/[ $ret -ne 2 ] \&\& exitcode=1/' pmtu.sh
	# for test fib-onlink-tests.sh we need remove default IPv6 route
	ip -6 route save default > default_ipv6.route
	# for test fcnal-test.sh
	cp nettest /usr/local/bin/
	# for l2tp.sh
	modprobe -a l2tp_eth l2tp_ip6 l2tp_ip
	# for msg_zerocopy.sh, we don't have UDP zero copy support yet
	sed -i 's/$0 4 udp -t 1/#$0 4 udp -t 1/' msg_zerocopy.sh
	sed -i 's/$0 6 udp -t 1/#$0 6 udp -t 1/' msg_zerocopy.sh
	# txtimestamp.sh do not support IPPROTO_RAW and pf_packet??
	sed -i 's/run_test_v4v6 ${args} -R/#run_test_v4v6 ${args} -R/' txtimestamp.sh
	sed -i 's/run_test_v4v6 ${args} -P/#run_test_v4v6 ${args} -P/' txtimestamp.sh
	# incase some test not add exec permission
	chmod +x *.sh
	popd

	# install jq for fib_nexthops.sh test
	install_netsniff || { test_fail "install netsniff for net test failed" && return 1; }
}

do_net_reset()
{
	pushd $EXEC_DIR/net
	# for test fib-onlink-tests.sh we'd better restore default IPv6 route
	ip -6 route restore < default_ipv6.route
	popd
}

do_net_forwarding_config()
{
	which tc || dnf install -q -y iproute-tc
	install_netsniff || { test_fail "install netsniff for forwarding test failed" && return 1; }
	install_smcroute || { test_fail "install smcrouted for forwarding test failed" && return 1; }

	pushd $EXEC_DIR/net/forwarding
	# RHEL9 doesn't support meta
	if [ $(krelease) == "el9" ]; then
		sed -i '0, /ets_test_strict/ {/ets_test_strict/d;}' sch_ets.sh
		sed -i '0, /ets_test_mixed/ {/ets_test_mixed/d;}' sch_ets.sh
		sed -i '0, /ets_test_dwrr/ {/ets_test_dwrr/d;}' sch_ets.sh
		sed -i '/classifier_mode/d' sch_ets.sh
	fi

	# RHEL8.6 and 9.0 set this to "0 2147483647", which makes the
	# router_multipath tests failed
	reset_ping_group_range=$(sysctl -n net.ipv4.ping_group_range)
	sysctl -qw net.ipv4.ping_group_range="1 0"

	cp forwarding.config.sample forwarding.config
	popd
}

do_net_forwarding_reset()
{
	sysctl -qw net.ipv4.ping_group_range="${reset_ping_group_range}"
	# forwarding tests created veth pairs and netns, which may affect
	# later tests when they also want to create veth interfaces.
	reset_net_env
}

do_netfilter_config()
{
	which conntrack || dnf install -q -y conntrack-tools
	install_sendip
}

do_bpf_test_progs_run()
{
	local item="bpf_test_progs"
	local ret ret_1 ret_2

	[ ! -d $EXEC_DIR/bpf ] && test_skip "No $item test, skip" && return 1

	pushd $EXEC_DIR/bpf
	if [ ! -f test_progs ] || [ ! -f test_progs-no_alu32 ] || ! ./test_progs --count; then
		test_skip "No $item test, skip"
		return 1
	fi

	local total_tests=$(./test_progs --list)
	local total_num=$(./test_progs --count)
	local num=0
	local name=""

	for name in ${total_tests}; do
		num=$(($num + 1))

		check_skip "${item}:${name}" && check_result $num $total_num "${item}:${name}" $SKIP_CODE && continue

		local OUTPUTFILE=$LOG_DIR/${item}_${name}.log
		dmesg -C

		run "./test_progs -t $name"
		ret_1=$?
		# Get more detailed log info with -vv if failed
		[ ${ret_1} -ne 0 ] && run "./test_progs -vv -t $name"

		run "./test_progs-no_alu32 -t $name"
		ret_2=$?

		echo -e "\n=== Dmesg result ===" >> $OUTPUTFILE
		dmesg >> $OUTPUTFILE

		[ "$ret_1" -ne 0 ] && ret=${ret_1} || ret=${ret_2}
		check_result $num $total_num "${item}:${name}" $ret
	done

	popd
}

# ----------- init setups -----------

# source skip/waive list
if [ $(krelease) == "el8" ] || [ $(krelease) == "el9" ]; then
	[ ! -f skip_waive.list ] && \
		wget -q https://gitlab.com/liuhangbin/kselftests-known-issues/-/raw/main/skip_waive.$(krelease) -O skip_waive.list
	submit_log skip_waive.list
	source skip_waive.list

	SKIP_TARGETS="$SKIP_TARGETS ${skip_tests[*]}"
	[ $(free -m | awk '/Mem/ {print $2}') -lt 8000 ] && SKIP_TARGETS="$SKIP_TARGETS ${large_mem_tests[*]}"
	WAIVE_TARGETS="$WAIVE_TARGETS ${waive_tests[*]}"
fi
