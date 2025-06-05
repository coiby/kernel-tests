#!/bin/bash
# shellcheck disable=SC2166,SC2320

# Summary: zswap feature test
# Author: Li Wang <liwang@redhat.com>

. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../include/libmem.sh || exit 1

set -o pipefail

OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/outputfile}
TASKID=${TASKID:-UNKNOWN}
ARCH=$(uname -m)

tmpdir=$(dirname $OUTPUTFILE)/zsawp_$TASKID

function arch_check()
{
	if [ ${ARCH} = s390x ] || [ ${ARCH} = i386 ]; then
		echo " zswap has not been supported on ${ARCH}" | tee -a $OUTPUTFILE
		rstrnt-report-result Test_Skipped PASS 99
		exit 0
	fi
}

function kconfig_check()
{
	grep CONFIG_ZSWAP=y /boot/config-$(uname -r)
	if [ ! $? = 0 ]; then
		echo "CONFIG_ZSWAP=y is not configured in this kernel $(uname -r)"
		exit 0
	fi
	return 0
}

function dist_check()
{
	local rhel=$(grep -Eo '[0-9]+.[0-9]+' /etc/redhat-release)
	if (echo ${rhel} "7.0" | awk '($1>$2){exit 1}') then
		echo "zswap is now only supported on RHEL7" | tee -a $OUTPUTFILE
		rstrnt-report-result Test_Skipped PASS 99
		exit 0
	fi
}

function stress_install()
{
	if [ ! -d stress-1.0.4 ]; then
		wget http://download.eng.rdu2.redhat.com/qa/rhts/lookaside/stress-1.0.4.tar.gz;
		tar xzf stress-1.0.4.tar.gz >/dev/null 2>&1
		pushd stress-1.0.4; ./configure >/dev/null 2>&1; make >/dev/null 2>&1 && make install >/dev/null 2>&1; popd
	fi
}

function set_zswap()
{
	export ZSWAP=$(sed -n  -e 's/"\(.*\)"\(.*\)/\1/g' -e '1p' $tmpdir/zswap_parameter.txt)
	export ZSWAP_TEST=$(sed -n  -e 's/"\(.*\)"\(.*\)/\2/g' -e '1p' $tmpdir/zswap_parameter.txt)
	rlRun "sed -i '1d' $tmpdir/zswap_parameter.txt"
}

function show_memory_info()
{
	echo -n "memory.current: "
	cat $cgroup_path/memory.current
	echo -n "memory.zswap.current: "
	cat $cgroup_path/memory.zswap.current
	echo -n "memory.swap.current: "
	cat $cgroup_path/memory.swap.current
}

function zswap_test()
{
	local mem_limit=$((use_mem + use_swap))
	local mem_test=$(echo $mem_limit \* 0.95 | bc | awk -F. '{print $1}')

	local stored_pages_1=$(cat /sys/kernel/debug/zswap/stored_pages)
	# debug
	rlRun -l "cat /sys/kernel/debug/zswap/stored_pages" 0-255
	local stored_pages_2=0

	# Running the stress process in background, if mem is less than 256G,
	# use one stress, otherwise, use nr_cpu stresses.
	local nproc
	local per_task_mem

	per_task_mem=$(echo $mem_test / $(nproc) | bc -q)
	nproc=$(nproc)
	if ((per_task_mem == 0)); then
		nproc=8
		per_task_mem=$(echo $mem_test / $nproc | bc -q)
	fi

	rlRun "cgexec.sh zswap_test memory stress --vm $nproc --vm-bytes ${per_task_mem}M --timeout 240s >/dev/null &"
	if [ $? -ne 0 ]; then
		echo "failed to run the process in background."
		exit 1
	fi

	local cgroup_path=$(cgroup_get_path zswap_test memory)
	if [ -n "$oom_score_adj" ]; then
		local spid
		for spid in $(cat $cgroup_path/$CGROUP_TASK_FILE); do
			echo "$spid: adjusting oom_score_adj to $oom_score_adj"
			ret=$(echo $oom_score_adj > /proc/$spid/oom_score_adj)
			[ $ret -ne 0 ] && echo "$spid: failed to adjust oom_score_adj"
		done
	fi

	# Checking if zswap work
	for i in $(seq 120); do
		local pages=$(cat /sys/kernel/debug/zswap/stored_pages)
		stored_pages_2=$(( $stored_pages_2 + $pages ))
		if ((i % 60 == 0)) && [ "$CGROUP_VERSION" = 2 ] && test -f $cgroup_path/memory.reclaim; then
			# 2g memory, trigger 50m reclaim to swap, this is not heavy.
			local reclaim_mem=50M
			echo "Before reclaim:"
			show_memory_info
			echo $reclaim_mem > $cgroup_path/memory.reclaim
			echo "After reclaim:"
			show_memory_info
		fi
		if ((i % 20 == 0)); then
			free -m
			ps -C stress -o pid,vsz,rsz,etimes,cgroup
			free_m=$(free -m | awk '/Mem/ {print $4}')
			echo "free mem MiB: $free_m"
		fi
		sleep 1
	done

	stored_pages_2=$(( $stored_pages_2 / 120 ))
	# debug
	rlRun -l "cat /sys/kernel/debug/zswap/stored_pages" 0-255

	# Kill the stress process
	killall stress >/dev/null 2>&1

	if [ "$stored_pages_2" -le "$stored_pages_1" ]; then
		return 1
	else
		return 0
	fi
}

function setup_cgroup()
{
	echo 3 > /proc/sys/vm/drop_caches
	free_swap_m=$(free -m | awk '/Swap/ {print $4; exit}')
	if ((free_swap_m == 0)); then
		lsblk
		swapoff -a
		swapon -a
		free_swap_m=$(free -m | awk '/Swap/ {print $4; exit}')
		if ((free_swap_m == 0)); then
			free_swap_m=64
		fi
	fi
	free_mem_m=$(free -m | awk '/Mem/ {print $4}')
	use_swap=$(echo $free_swap_m \* 0.9 | bc | awk -F. '{print $1}')
	use_mem=2048
	# Leave some memory for system processes
	if ((free_mem_m < 3072)); then
		use_mem=$(echo $free_mem_m \* 0.5 | bc | awk -F. '{print $1}')
	fi

	check_cgroup_version
	cgroup_create zswap_test memory
	free -m
	cgroup_set_memory zswap_test ${use_mem}m ${use_swap}m
	cgroup_set_file zswap_test memory memory.oom_control=1
	[ $? -ne 0 ] && oom_score_adj=-1000
	echo -1000 > /proc/self/oom_score_adj
	cat /proc/self/oom_score_adj
}

# ----- Test Start ------
rlJournalStart

rlPhaseStartSetup
	# Run only once
	if [ ! -d $tmpdir ]; then
		rlRun "dist_check"
		rlRun "arch_check"
		rlRun "kconfig_check"
		rlRun "mkdir -p $tmpdir"
		# Until now, deflate/lz4 compressor has not been supported in RHE7.
		# So, the parameters recored in a local file as a stack to make
		# sure it could be extended in future.
		cat <<EOF >$tmpdir/zswap_parameter.txt
"zswap.enabled=1"test0
"zswap.enabled=1 zswap.max_pool_percent=17"test1
"stop"test2
"exit"
EOF
		rlRun "stress_install"
		yum_dnf=yum
		which dnf 2>/dev/null && yum_dnf=dnf
		which bc 2>/dev/null || $yum_dnf -y install bc
		which killall 2>/dev/null || $yum_dnf -y install psmisc
	fi

	setup_cgroup

rlPhaseEnd

skip_runtime=0
rlPhaseStartTest
	rlRun "set_zswap"
	if [ -z "$ZSWAP" ]; then
		rlFail "ZSWAP parameter is empty."
	fi
	major_r=$(uname -r | cut -d. -f 1)
	minor_r=$(uname -r | cut -d. -f 2)
	if [ "$major_r" -le 3 ] || ( [ "$major_r" -eq 4 ] && [ "$minor_r" -lt 17 ] ); then
		rlLog "Don't support runtime update!"
		ls /sys/module/zswap/parameters/ -l
		skip_runtime=1
	fi

	case $ZSWAP_TEST in
		test0)
			rlRun "echo Test0"
			if [ "$skip_runtime" = 0 ]; then
				# Enable zswap in runtime
				rlRun "echo 1 > /sys/module/zswap/parameters/enabled"
				rlRun "grep Y /sys/module/zswap/parameters/enabled"
				rlRun "grep 20 /sys/module/zswap/parameters/max_pool_percent"
				rlRun "zswap_test" 0 "Expect zswap_test() return 0, PASS."

				# Disable zswap in runtime
				rlRun "echo 0 > /sys/module/zswap/parameters/enabled"
				rlRun "grep N /sys/module/zswap/parameters/enabled"
				rlRun "zswap_test" 1 "Expect zswap_test() return 1, PASS."
			fi
			;;
		test1)
			# Enable zswap from cmdline
			rlRun "echo Test1"
			rlRun "cat /proc/cmdline" -l
			rlRun "grep Y /sys/module/zswap/parameters/enabled"
			rlRun "grep zbud /sys/module/zswap/parameters/zpool"
			rlRun "grep 20 /sys/module/zswap/parameters/max_pool_percent"
			rlRun "grep lzo /sys/module/zswap/parameters/compressor"
			rlRun "zswap_test" 0 "Expect zswap_test() return 0, PASS."
			;;
		test2)
			rlRun "echo Test2"
			rlRun "cat /proc/cmdline"
			rlRun "grep 17 /sys/module/zswap/parameters/max_pool_percent"
			rlRun "zswap_test" 0 "Expect zswap_test() return 0, PASS."

			# Test if zswap could handle 0% in max_pool_percent
			rlRun "echo 0 > /sys/module/zswap/parameters/max_pool_percent"
			rlRun "grep 0 /sys/module/zswap/parameters/max_pool_percent"
			rlRun "zswap_test" 1 "Expect zswap_test() return 1, PASS."

			for ((i = 0; i <= 100; i += 10))
			{
				rlRun "echo $i > /sys/module/zswap/parameters/max_pool_percent"
				rlRun "grep $i /sys/module/zswap/parameters/max_pool_percent"
			}
			;;
	esac

	if [ "$ZSWAP" = "stop" ] || [ "$ZSWAP" = "exit" ]; then
		rlRun "grubby --update-kernel=DEFAULT --remove-args=\"zswap.enabled=1 zswap.max_pool_percent=17\""
	else
		rlRun "grubby --update-kernel=DEFAULT --remove-args=\"zswap.enabled=1 zswap.max_pool_percent=17\""
		rlRun "grubby --update-kernel=DEFAULT --args=\"$ZSWAP\""
	fi
rlPhaseEnd

if [ "$ZSWAP" != "exit" ]; then
	rstrnt-reboot
fi

rlPhaseStartCleanup
	rlRun "rm -r $tmpdir"
	cgroup_destroy zswap_test memory
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
