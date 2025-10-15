#!/bin/bash

# include beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../../cki_lib/libcki.sh || exit 1
. ../../../../cmdline_helper/libcmd.sh || exit 1

set -o pipefail

OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/outputfile}
TASKID=${TASKID:-UNKNOWN}

tmpdir=/var/tmp/mem_$TASKID
kmem_peak=$(cat /sys/fs/cgroup/memory/memory.kmem.max_usage_in_bytes)
cur_used=$(free | awk '/Mem/ {print $3}')


function set_mem()
{
	# added these Memory compare to make sure this case as a
	# general test case to cover "mem=" parameter in kernel
	MEM_TOTAL=$(free | sed -n "s/^Mem:\s*\([0-9]\+\).*\$/\1/p")
	echo "MEM_TOTAL= $MEM_TOTAL kB"
	if [ "$MEM_TOTAL" -ge 1073741824 ]; then
		export MEM="${MEM:-1024G}"
	elif [ "$MEM_TOTAL" -ge 536870912 ]; then
		export MEM="${MEM:-65536M 128G 0x500000000}"
	elif [ "$MEM_TOTAL" -ge 12582912 ]; then
		# For ppc64le on rhel-alt, 12G caused oom, system with 500G memory.
		local szlist="12G"
		local factor=12

		hostname | grep p9b
		[ $? = 0 ] && szlist="24G" && factor=24

		local comp=$((factor * 1024 * 1024 * 1024))
		local nproc=$(nproc)
		local inG

		if [[ "$cur_used" -gt "$comp" && "$kmem_peak" -ne 0 && "$kmem_peak" -gt "$cur_used" ]]; then
			szlist=$((kmem_peak + nproc * 1024 * 1024 * 32))
			inG=$((szlist /1024/1024/1024 + 1))
			szlist+=" ${inG}G"
		elif [[ "$cur_used" -ne 0 && "$cur_used" -gt $comp ]]; then
			inG=$((cur_used / 1024 / 1024 / 1024 + nproc * 32 / 1024 + 1))
			szlist="$((cur_used + nproc * 1024 * 1024 * 32))"
			szlist+=" ${inG}G"
		fi
		export MEM="${MEM:-${szlist:-12G 0x200000000}}"
	elif [ "$MEM_TOTAL" -ge 8388608 ]; then
		export MEM="${MEM:-4096M 0x200000000}"
	elif [ "$MEM_TOTAL" -ge 4194304 ]; then
		export MEM="${MEM:-4096M}"
	else
		echo "Sorry, the system RAM is too low to test."
		if [[ -n "${TMT_TEST_NAME}" ]]; then
			RSTRNT_TASKNAME="${TMT_TEST_NAME}"
		fi
		rstrnt-report-result $RSTRNT_TASKNAME SKIP
		return 4
	fi
	echo "set_mem: MEM=$MEM"

	return 0
}

function kilobytes()
{
	case ${1:-0} in
		*G)
			echo $(( ${1%G} * 1024 * 1024 ))
			;;
		*M)
			echo $(( ${1%M} * 1024 ))
			;;
		*k)
			echo $(( ${1%k} ))
			;;
		*)
			echo $(( $1 / 1024 ))
			;;
	esac
}

rlJournalStart

if [ ! -d "$tmpdir" ]; then
	rlPhaseStartSetup
		# setup MEM paramenter
		rlRun "set_mem" "0,4"
		if [ $? -ne 0 ]; then
			rlPhaseEnd
			rlJournalEnd
			exit 0
		fi

		if [ -z "$MEM" ]; then
			rlFail "MEM parameter is empty."
		fi
		rlRun "mkdir -p $tmpdir"
		rlRun "pushd $tmpdir"
		echo "start" > list
		for x in $MEM; do
			echo "$x" >> list
		done
		echo "stop" >> list
		echo "exit" >> list
		rlRun "popd"
	rlPhaseEnd
fi

rlPhaseStartTest
	rlRun "pushd $tmpdir"
	# For better debug
	rlRun -l "free"
	rlRun -l "cat /proc/meminfo"
	test -d /sys/devices/system/node && rlRun -l "find /sys/devices/system/node/ -name meminfo -exec cat {} \;"
	rlRun -l "echo m > /proc/sysrq-trigger"
	rlRun -l "cat /proc/zoneinfo"

	# According to the current kmem/mem usage status, help to determine the minimum
	# mem=, otherwise, oom can be seen (on power9 p9b machines)
	rlRun -l "cat /sys/fs/cgroup/memory/memory.kmem.max_usage_in_bytes" 0-255
	rlRun -l "free | awk '/Mem/ {print $3}'" 0-255 "Get the current used memory" 0-255

	# mem parameter for running kernel
	rlRun "current=$(sed -n '1p' list)"
	# mem parameter to be set for next reboot
	rlRun "next=$(sed -n '2p' list)"
	rlRun "sed -i '1d' list"
	# shellcheck disable=SC2154
	rlLog "current=$current next=$next"

	rlRun -l 'free_total=$(free | sed -n "s/^Mem:\s*\([0-9]\+\).*\$/\1/p")'
	# shellcheck disable=SC2154
	rlLog "Total memory (reported by 'free') $free_total kB"
	rlRun -l "dmesg_total=\$(journalctl -k | sed -n 's/^.*Memory:\\s*[0-9]\\+K\\s*\\/\\s*\\([0-9]\\+\\)K\\s*available.*$/\1/ip')"

	if [[ "$current" != "start" && "$current" != "stop" ]]; then
		# check if the kernel parameter is set
		rlRun "cat /proc/cmdline | grep \"mem=$current\""
		rlLog "mem=$current which is $(kilobytes $current) kB"
		rlRun -l "mem_absent=\$(journalctl -k | sed -n 's/.*\\ \\([0-9]\\+\\)[Kk]\ absent.*$/\1/p')"

		rlRun -l "dmesg_total=\$(journalctl -k | sed -n 's/^.*Memory:\\s*[0-9]\\+K\\s*\\/\\s*\\([0-9]\\+\\)K\\s*available.*$/\1/ip')"
		if [ -n "$mem_absent" ]; then
			rlLog "Absent memory (from dmesg message) $mem_absent kB"
			# shellcheck disable=SC2154
			rlRun "dmesg_total=\$(($dmesg_total - $mem_absent))"
		fi

		rlLog "Total memory (from dmesg message) $dmesg_total kB"

		rlRun "[ -n \"$free_total\" -a -n \"$dmesg_total\" -a -n \"$current\" ]"

		if [ "$(uname -m)" != aarch64 ]; then
			retval=0
		else
			rlLogInfo "aarch64 bz1666362, skip checking result"
			retval=0-255
		fi
		rlRun "[ ${free_total:-X} -le $(kilobytes $current) ]" $retval

		rlRun "[ ${dmesg_total:-X} -le $(kilobytes $current) ]" $retval
	fi

	if [ "$next" == "stop" ]; then
		rlRun "change_cmdline -mem"
	elif [ "$next" != "exit" ]; then
		rlRun "change_cmdline mem=${next}"
	fi

	rlRun "popd"
rlPhaseEnd

if [ "$next" != "exit" ]; then
	rstrnt-reboot
fi

rlPhaseStartCleanup
	rlRun "rm -r $tmpdir"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
