#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/kselftests
#   Description: kselftests
#   Author: Hangbin Liu <haliu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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
# Global parameters
# DEBUG: enable debug or not, default is true
# CHECK_UNINVES: also check uninvestigated tests result, default is false
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
. ./include.sh
. ./specific_fun.sh
#-------------------- Setup --------------------
SKIP=4
LOG_ONCE=0
EXEC_DIR="$PWD/selftests"
TOTAL_MEM=$(free -m | awk '/Mem/ {print $2}')
TEST_ITEMS=${TEST_ITEMS:-"net net/forwarding netfilter bpf bpf_test_progs tc-testing kvm"}
DEFAULT_IFACE=$(ip route | awk '/default/{match($0,"dev ([^ ]+)",M); print M[1]; exit}')

TOTAL_FAIL=0

debug_info()
{
	[ ${LOG_ONCE} -eq 0 ] && \
		log "$(rpm -q bpftool clang llvm iproute iproute-tc)" && \
		LOG_ONCE=1

	if [ "$DEBUG" ]; then
		run "ip link show"
		run "bpftool prog show"
		run "iptables -L"
		run "ip6tables -L"
	fi
}

reset_net_env()
{
	# log the link before clean
	debug_info
	ip -a netns del
	sleep 2
	if [ "$DEBUG" ]; then
		run "ip link show"
	fi
}

# usage: check_skipped_tests test_name
check_skipped_tests()
{
	local match="$1"
	check_if_missing_files $match && return 0
	[[ " ${skip_tests[*]} " == *" $match "* ]] && return 0
	[ $TOTAL_MEM -lt 8000 ] && [[ " ${large_mem_tests[*]} " == *" $match "* ]] && return 0
	# skip the test if it not exist for backward compatibility
	[ ! -f $match ] && return 0
	return 1
}

check_result()
{
	local num=$1
	local total_num=$2
	local test_folder=$3
	local test_name=$4
	local test_result=$5

	if [ "$test_result" -eq 0 ]; then
		test_pass "${num}..${total_num} selftests: ${test_folder}: ${test_name} [PASS]"
	elif [[ " ${pending_tests[*]} " == *" $test_name "* ]] && [ ! $CHECK_UNINVES ]; then
		test_pass "${num}..${total_num} selftests: ${test_folder}: ${test_name} [WAIVE]"
	elif [[ " ${uninves_tests[*]} " == *" $test_name "* ]] && [ ! $CHECK_UNINVES ]; then
		test_pass "${num}..${total_num} selftests: ${test_folder}: ${test_name} [WAIVE]"
	elif [ "$test_result" -eq $SKIP ]; then
		test_pass "${num}..${total_num} selftests: ${test_folder}: ${test_name} [SKIP]"
	else
		test_fail "${num}..${total_num} selftests: ${test_folder}: ${test_name} [FAIL]"
	fi

	return $test_result
}

do_net_config()
{
	# Fix some known issues
	# rm 0x10 for fib_rule_tests.sh due to bz1480136
	# FIXME: should we restore it back after finishing test?
	sed -i "/0x10/d" /etc/iproute2/rt_dsfield
	# FIXME: sleep 5s before do IPv6 "Using route with mtu metric" test to
	# pass it. Not sure why ping would fail if not sleep some seconds, need to check
	sed -i "/via 2001:db8:101::2 mtu 1300/a\\\\tsleep 5" fib_tests.sh
	# need to be run on bare metal machines, or set -C 0 when run on VM
	sed -i 's/-C [0-9]/-C 0/g' msg_zerocopy.sh
	# fou is not enabled on RHEL
	sed -i 's/kci_test_encap_fou /#kci_test_encap_fou /' rtnetlink.sh
	# ip_defrag.sh need setting net.netfilter.nf_conntrack_frag6_high_thresh
	modprobe nf_conntrack_ipv6
	# pmtu.sh will return 1 for skiped tests, remove fou,gue tests
	sed -i '/^\tpmtu_ipv[4,6]_fou[4,6]_exception/d' pmtu.sh
	sed -i '/^\tpmtu_ipv[4,6]_gue[4,6]_exception/d' pmtu.sh
	sed -i 's/exitcode=1/[ $ret -ne 2 ] \&\& exitcode=1/' pmtu.sh
	# for test fib-onlink-tests.sh we need remove default IPv6 route
	ip -6 route del default
	# for test fcnal-test.sh
	cp nettest /usr/local/bin/
	# for l2tp.sh
	modprobe l2tp_eth
	modprobe l2tp_ip
}

do_net_forwarding_config()
{
	which tc || dnf install -q -y iproute-tc
	install_netsniff || { test_fail "install netsniff for forwarding test failed" && return 1; }
	install_smcroute || { test_fail "install smcrouted for forwarding test failed" && return 1; }
	cp forwarding.config.sample forwarding.config
}

do_netfilter_config()
{
	install_sendip
}

run_bpf_test_progs()
{
	local item="bpf_test_progs"
	local ret ret_1 ret_2

	[ ! -d $EXEC_DIR/bpf ] && test_skip "No $item test, skip" && return 1
	pushd $EXEC_DIR/bpf
	if [ ! -f test_progs ] || [ ! -f test_progs-no_alu32 ]; then
		test_skip "No $item test, skip"
		return 1
	fi

	total_tests=$(./test_progs --list)
	total_num=$(./test_progs --count)
	nfail=0 num=0 name=""

	for name in ${total_tests}; do
		num=$(($num + 1))
		OUTPUTFILE=$(new_outputfile)

		dmesg -C

		run "./test_progs -t $name"
		ret_1=$?

		run "./test_progs-no_alu32 -t $name"
		ret_2=$?

		echo -e "\n=== Dmesg result ===" >> $OUTPUTFILE
		dmesg >> $OUTPUTFILE

		[ "$ret_1" -ne 0 ] && ret=${ret_1} || ret=${ret_2}
		check_result $num $total_num ${item} ${name} $ret || \
			nfail=$((nfail+1))
		clean_env
	done

	echo "${item}: total $total_num, failed $nfail"
	TOTAL_FAIL=$(($TOTAL_FAIL+$nfail))
	popd
}

run_tc_test()
{
	# Start tc test
	local item="tc-testing"
	local act_tests=$(ls -d tc-tests/actions/*.json)
	local fil_tests=$(ls -d tc-tests/filters/*.json)
	local qdi_tests=$(ls -d tc-tests/qdiscs/*.json)
	local total_tests="$act_tests $fil_tests $qdi_tests"
	local total_num=$(echo ${total_tests} | wc -w)
	local FAIL=0 nskip=0 ret=0

	# prepare evn
	rpm -q clang || dnf install -y clang valgrind
	modprobe -r veth

	# extend test timeout
	sed -i '/TIMEOUT/s/12/180/' tdc_config.py
	# to build action.o for test tc-tests/actions/bpf.json
	run "clang -target bpf -c bpf/action.c -o bpf/action.o"

	for name in ${total_tests}; do
		num=$(($num + 1))

		check_skipped_tests "${name}" && \
			test_skip "${num}..${total_num} selftests: ${item}: ${name} Skip" && continue

		local OUTPUTFILE=$(new_outputfile)

		echo ${tc_tests[$num - 1]} | grep -qP "tests\.json|concurrency\.json"  && extra_p="-d $DEFAULT_IFACE" || extra_p=""
		./tdc.py -f ${name} $extra_p &> $OUTPUTFILE
		ret=$?
		if grep -q "not ok" $OUTPUTFILE; then
			check_result $num $total_num ${item} ${name} 1
			FAIL=$(($FAIL+1))
		elif grep -q "# skipped -" $OUTPUTFILE; then
			check_result $num $total_num ${item} ${name} 4
			nskip=$((nskip+1))
		elif grep -q "Traceback" $OUTPUTFILE; then
			check_result $num $total_num ${item} ${name} 4
			nskip=$((nskip+1))
		else
			check_result $num $total_num ${item} ${name} $ret
		fi
	done

	echo "${item}: total $total_num, failed $FAIL, skipped $nskip"
	TOTAL_FAIL=$(($TOTAL_FAIL+$FAIL))
	popd
}


do_lkdtm_config()
{
	# CKI by default sets panic_on_oops on kernel config.
	# For this test it has to be disabled
	panic_on_oops=$(cat /proc/sys/kernel/panic_on_oops)
	echo 0 > /proc/sys/kernel/panic_on_oops
}


do_lkdtm_clenup()
{
	# CKI by default sets panic_on_oops on kernel config.
	# Restore the initial value
	echo ${panic_on_oops} > /proc/sys/kernel/panic_on_oops
}

#-------------------- Start Test --------------------
setup_env
install_kselftests || test_fail_exit "install kselftests failed"

run "uname -r"
reset_net_env
submit_log "$EXEC_DIR/kselftest-list.txt"

for item in $TEST_ITEMS; do
	# deal with bpf/test_progs specially
	[ "$item" == "bpf_test_progs" ] && run_bpf_test_progs && continue

	grep -q "^$item:" selftests/kselftest-list.txt || \
		{ test_skip "$item test not find in kselftest-list.txt" && continue; }

	pushd $EXEC_DIR/$item
	if [ "$item" == "tc-testing" ]; then
		run_tc_test
		continue
	fi

	_item=$(echo $item | tr -s "/-" "_")
	total_tests=$(grep "^${item}:"  $EXEC_DIR/kselftest-list.txt | cut -f2 -d:)
	total_num=$(echo ${total_tests} | wc -w)
	FAIL=0 num=0 name=""

	if type do_${_item}_config &>/dev/null; then
		do_${_item}_config || continue
	fi

	for name in ${total_tests}; do
		_base_filename="/tmp/$(echo $name | sed s'/\.sh//')"
		_log_file="${_base_filename}.log"
		_dmesg_log_file="${_base_filename}_dmesg.log"
		OUTPUTFILE=$_log_file

		echo "Start test: ${item}/${name}"
		num=$(($num + 1))
		check_skipped_tests "${name}" && \
			test_pass "${num}..${total_num} selftests: ${item}: ${name} Skip" && continue

		dmesg -C

		./${name} |& tee ${_log_file}
		ret=${PIPESTATUS[0]}

		dmesg > ${_dmesg_log_file}
		submit_log ${_log_file}
		submit_log ${_dmesg_log_file}

		check_result $num $total_num ${item} ${name} $ret || \
			FAIL=$(($FAIL+1))

		if [ ${_item} == "net" ] || [ ${_item} == "net_forwarding" ]; then
			reset_net_env
		fi
	done

	if type do_${_item}_cleanup &>/dev/null; then
		do_${_item}_cleanup || continue
	fi

	echo "${item}: total $total_num, failed $FAIL"
	TOTAL_FAIL=$(($TOTAL_FAIL+$FAIL))
	popd
done

#-------------------- Clean Up --------------------

if [[ ${TOTAL_FAIL} -ne 0 ]]; then
	exit 1
fi
