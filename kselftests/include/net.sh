#!/bin/sh
# This file is used for network related tests configurations.

# use it in a separate shell in case variables tainted
# rhel_mjor defined in include.sh
krelease=$(rhel_major)

# These variables are set on runtest.sh, this script should only be run within runtest.sh
declare pkg_mgr pkg_mgr_inst_string skip_tests

get_default_iface()
{
	ip route | awk '/default/{match($0,"dev ([^ ]+)",M); print M[1]; exit}'
}

install_netsniff()
{
	which mausezahn && return 0

	if [ "${krelease}" -eq "8" ] || [ "${krelease}" -eq "9" ]; then
		if ! rpm -q --quiet epel-release; then
			# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
			$pkg_mgr $pkg_mgr_inst_string  https://dl.fedoraproject.org/pub/epel/epel-release-latest-"${krelease}".noarch.rpm
			local need_remove=1
		else
			if [ "$pkg_mgr" != "rpm-ostree" ]; then
				local param="--enablerepo=epel"
			fi
		fi
	fi

	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string $param jq netsniff-ng

	[ "${need_remove}" ] && $pkg_mgr -y remove epel-release

	which mausezahn && return 0 || return 1
}

install_iptables_legacy()
{
	rpm -q --quiet iptables-legacy && return 0

	if [ "${krelease}" -eq "8" ] || [ "${krelease}" -eq "9" ]; then
		if ! rpm -q --quiet epel-release; then
			# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
			$pkg_mgr $pkg_mgr_inst_string  https://dl.fedoraproject.org/pub/epel/epel-release-latest-"${krelease}".noarch.rpm
			local need_remove=1
		else
			local param="--enablerepo=epel"
		fi
	fi

	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string $param iptables-legacy

	[ "${need_remove}" ] && $pkg_mgr -y remove epel-release

	rpm -q --quiet iptables-legacy && return 0 || return 1
}

install_smcroute()
{
	which smcroute && return 0
	dnf copr -y enable liuhangbin/smcroute
	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string smcroute
	which smcroute && return 0 || return 1
}

install_sendip()
{

	which sendip && return 0
	dnf -y copr enable cygn/SendIP
	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string sendip

	which sendip && return 0 || return 1
}

install_scapy()
{
	scapy -h && return 0
	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	[ "${krelease}" -eq "8" ] && \
		$pkg_mgr $pkg_mgr_inst_string https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string scapy
	[ "${krelease}" -eq "8" ] && rpm -e epel-release
	scapy -h && return 0 || return 1
}

# Config Networkmanager to ignore network interfaces except default port.
# Edit /usr/lib/udev/rules.d/85-nm-unmanaged.rules with rule like
# ENV{ID_NET_DRIVER}=="ipip", ENV{NM_UNMANAGED}="1"
# also works, but it only takes care one driver.
set_nm_unmanage()
{
	local default_iface=$(get_default_iface)

	# ignore ports except default port
	echo "[keyfile]" >> /etc/NetworkManager/NetworkManager.conf
	echo "unmanaged-devices=except:interface-name:$default_iface" \
		>> /etc/NetworkManager/NetworkManager.conf

	systemctl restart NetworkManager
}

# You'd better restore the configuration at the end of your case.
unset_nm_unmanage()
{
	sed -i '/\[keyfile\]/d' /etc/NetworkManager/NetworkManager.conf
	sed -i '/unmanaged-devices/d' /etc/NetworkManager/NetworkManager.conf

	systemctl restart NetworkManager
}

# some common network setups
set_network_env()
{
	set_nm_unmanage
	return 0
}

# common network resets
reset_network_env()
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
	modprobe -r br_netfilter
	ip -a netns del
	sleep 2

	# call unset_nm_unmanage() here as each reset function will call
	# reset_network_env()
	unset_nm_unmanage
	return 0
}

do_net_config()
{
	set_network_env

	pushd "$EXEC_DIR"/net || exit
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
	chmod +x ./*.sh
	popd || exit

	# install jq for fib_nexthops.sh test
	install_netsniff || { test_fail "install netsniff for net test failed" && return 1; }
}

do_net_reset()
{
	pushd "$EXEC_DIR"/net || exit
	# for test fib-onlink-tests.sh we'd better restore default IPv6 route
	ip -6 route restore < default_ipv6.route
	popd || exit

	reset_network_env
}

do_net_forwarding_config()
{
	set_network_env

	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	which tc || $pkg_mgr $pkg_mgr_inst_string iproute-tc
	install_netsniff || { test_fail "install netsniff for forwarding test failed" && return 1; }
	install_smcroute || { test_fail "install smcrouted for forwarding test failed" && return 1; }

	pushd "$EXEC_DIR"/net/forwarding || exit
	# RHEL9 doesn't support meta
	if [ "${krelease}" -eq "9" ]; then
		sed -i '0, /ets_test_strict/ {/ets_test_strict/d;}' sch_ets.sh
		sed -i '0, /ets_test_mixed/ {/ets_test_mixed/d;}' sch_ets.sh
		sed -i '0, /ets_test_dwrr/ {/ets_test_dwrr/d;}' sch_ets.sh
		sed -i '/classifier_mode/d' sch_ets.sh
	fi

	# RHEL8.6 and 9.0 set this to "0 2147483647", which makes the
	# router_multipath tests failed
	sysctl_set net.ipv4.ping_group_range "1 0"
	if lsmod | grep -q br_netfilter; then
		sysctl_set net.bridge.bridge-nf-call-iptables 0
		sysctl_set net.bridge.bridge-nf-call-ip6tables 0
	fi

	cp forwarding.config.sample forwarding.config
	popd || exit
}

do_net_forwarding_reset()
{
	sysctl_restore net.ipv4.ping_group_range
	if lsmod | grep -q br_netfilter; then
		sysctl_restore net.bridge.bridge-nf-call-iptables
		sysctl_restore net.bridge.bridge-nf-call-ip6tables
	fi
	# forwarding tests created veth pairs and netns, which may affect
	# later tests when they also want to create veth interfaces.
	reset_network_env
}

do_net_mptcp_config()
{
	set_network_env
}

do_net_mptcp_reset()
{
	reset_network_env
}

do_netfilter_config()
{
	set_network_env

	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	which conntrack || $pkg_mgr $pkg_mgr_inst_string conntrack-tools
	install_sendip
}

do_netfilter_reset()
{
	reset_network_env
}

do_bpf_config()
{
	set_network_env
}

do_bpf_reset()
{
	reset_network_env
}

# Download upstream bpf DENYLIST and update the waive list
update_bpf_waive_list()
{
	local link="https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf.git/plain/tools/testing/selftests/bpf/DENYLIST"
	local arch=$(uname -m)
	local prog

	if ! wget -q ${link}.${arch} -O /tmp/DENYLIST; then
		wget -q ${link} -O /tmp/DENYLIST
	fi

	for prog in $(cat /tmp/DENYLIST | grep -v "^#" | awk '{print $1}' | cut -f 1 -d '/'); do
		WAIVE_TARGETS="$WAIVE_TARGETS bpf_test_progs:${prog}"
	done

	log "WAIVE_TARGETS are $WAIVE_TARGETS"
	submit_log /tmp/DENYLIST
}

do_bpf_test_progs_config()
{
	set_network_env
	update_bpf_waive_list

	# bz1969582 - the bpf:test_progs tests hit an expected mmap_zero avc
	# denial, unless we first turn mmap_low_allowed on
	echo "=== Setting mmap_low_allowed on ===" | tee -a "$OUTPUTFILE"
	setsebool -P mmap_low_allowed on
	sysctl_set net.mptcp.enabled 1
	sysctl_set kernel.io_uring_disabled 0
	modprobe nf_conntrack
	modprobe nf_nat

	install_iptables_legacy || test_warn "Install iptables-legacy failed"
}

do_bpf_test_progs_run()
{
	local item="bpf_test_progs"
	local ret ret_1 ret_2 name_opt

	[ ! -d "$EXEC_DIR"/bpf ] && test_skip "No $item test, skip" && return 1

	pushd "$EXEC_DIR"/bpf || exit
	if [ ! -f test_progs ] || [ ! -f test_progs-no_alu32 ] || ! ./test_progs --count; then
		test_skip "No $item test, skip"
		return 1
	fi

	local total_tests=$(./test_progs --list)
	local total_num=$(./test_progs --count)
	local num=0
	local name=""

	# -t will run tests with names containing any string from NAMES list
	./test_progs --help | grep -q "allow=NAMES" && name_opt="-a" || name_opt="-t"

	for name in ${total_tests}; do
		num=$((num + 1))

		check_skip "${item}:${name}" && test_skip "${num}..${total_num} selftests: ${item}:${name} [SKIP]" && continue

		local OUTPUTFILE=$LOG_DIR/${item}_${name}.log
		dmesg -C

		run "./test_progs ${name_opt} $name"
		ret_1=$?
		# Get more detailed log info with -vv if failed
		[ ${ret_1} -ne 0 ] && run "./test_progs -vv ${name_opt} $name"

		# bpf_nf test opened a tcp port, which will be in TIME-WAIT after close.
		echo "${name}" | grep -q "bpf_nf" && sleep 65

		run "./test_progs-no_alu32 ${name_opt} $name"
		ret_2=$?

		echo -e "\n=== Dmesg result ===" >> "$OUTPUTFILE"
		dmesg >> "$OUTPUTFILE"

		[ "$ret_1" -ne 0 ] && ret=${ret_1} || ret=${ret_2}
		check_result $num "$total_num" "${item}:${name}" $ret
	done

	popd || exit
}

do_bpf_test_progs_reset()
{
	# after testing completes, turn mmap_low_allowed off again
	echo "=== Setting mmap_low_allowed off ===" | tee -a "$OUTPUTFILE"
	setsebool -P mmap_low_allowed off
	sysctl_restore net.mptcp.enabled
	sysctl_restore kernel.io_uring_disabled
	modprobe -r nf_nat
	modprobe -r nf_conntrack
	reset_network_env
}

do_tc-testing_config()
{
	set_network_env

	# prepare evn
	# shellcheck disable=SC2086 # disabled on purpose as we want pkg_mgr_inst_string to expand
	$pkg_mgr $pkg_mgr_inst_string clang valgrind
	install_scapy
	pip -q install pyroute2 2>/dev/null
	modprobe -r veth
	modprobe netdevsim

	pushd "$EXEC_DIR"/tc-testing || exit
	# extend test timeout
	sed -i '/TIMEOUT/s/24/180/' tdc_config.py
	sed -i 's/python3 -s/python3/' *.py plugin-lib/*.py
	popd || exit
}

do_tc-testing_run()
{
	# Start tc test
	local item="tc-testing"

	[ ! -d "$EXEC_DIR"/${item} ] && test_skip "No $item test, skip" && return 1

	pushd "$EXEC_DIR"/${item} || exit

	local act_tests=$(ls -d tc-tests/actions/*.json)
	local fil_tests=$(ls -d tc-tests/filters/*.json)
	local qdi_tests=$(ls -d tc-tests/qdiscs/*.json)
	local total_tests="$act_tests $fil_tests $qdi_tests"
	local total_num=$(echo "${total_tests}" | wc -w)
	local DEFAULT_IFACE=$(ip route | awk '/default/{match($0,"dev ([^ ]+)",M); print M[1]; exit}')
	local fail=0 nskip=0 ret=0

	for name in ${total_tests}; do
		num=$((num + 1))

		check_skip "${item}:${name}" && test_skip "${num}..${total_num} selftests: ${item}:${name} [SKIP]" && continue

		local OUTPUTFILE=$LOG_DIR/$(echo "${name}" | tr '/' '_').log

		echo "${name}" | grep -qP "tests\.json|concurrency\.json" && extra_p="-d $DEFAULT_IFACE" || extra_p=""
		./tdc.py -f "${name}" "$extra_p" &> "$OUTPUTFILE"
		ret=$?
		if grep -q "not ok" "$OUTPUTFILE"; then
			check_result $num "$total_num" "${item}:${name}" 1
			fail=$((fail+1))
		elif grep -q "# skipped -" "$OUTPUTFILE"; then
			check_result $num "$total_num" "${item}:${name}" "$SKIP_CODE"
			nskip=$((nskip+1))
		elif grep -q "Traceback" "$OUTPUTFILE"; then
			check_result $num "$total_num" "${item}:${name}" "$SKIP_CODE"
			nskip=$((nskip+1))
		else
			check_result $num "$total_num" "${item}:${name}" $ret
		fi
	done

	echo "${item}: total $total_num, failed $fail, skipped $nskip"

	popd || exit
}

do_tc-testing_reset()
{
	reset_network_env
}
# ----------- init setups -----------

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	# source skip/waive list
	if [ "${krelease}" -eq "8" ] || [ "${krelease}" -eq "9" ]; then
		[ ! -f skip_waive.list ] && \
			wget -q https://gitlab.com/liuhangbin/kselftests-known-issues/-/raw/main/skip_waive."${krelease}" -O skip_waive.list
		[ ! -f param.list ] && \
			wget -q https://gitlab.com/liuhangbin/kselftests-known-issues/-/raw/main/param."${krelease}" -O param.list
	else
		# This list is used for upstream testing
		[ ! -f skip_waive.list ] && \
			wget -q https://gitlab.com/liuhangbin/kselftests-known-issues/-/raw/main/skip_waive.list -O skip_waive.list
		[ ! -f param.list ] && \
			wget -q https://gitlab.com/liuhangbin/kselftests-known-issues/-/raw/main/param.list -O param.list
	fi

	if [ $(wc -l skip_waive.list | cut -f 1 -d ' ') -ne 0 ]; then
		submit_log skip_waive.list
		source skip_waive.list

		SKIP_TARGETS="$SKIP_TARGETS ${skip_tests[*]}"
		[ $(free -m | awk '/Mem/ {print $2}') -lt 8000 ] && SKIP_TARGETS="$SKIP_TARGETS ${large_mem_tests[*]:-}"
		WAIVE_TARGETS="$WAIVE_TARGETS ${waive_tests[*]:-}"

	fi

	if [ $(wc -l param.list | cut -f 1 -d ' ') -ne 0 ]; then
		submit_log param.list

		while read -r line; do
			echo "$line" | grep "^#" && continue
			TEST_PARAMS="${line};$TEST_PARAMS"
		done < param.list
	fi
fi
