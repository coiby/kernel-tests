#!/bin/bash
# shellcheck disable=SC2034
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/sched-loadavg_test
#   Description: schedule loadavg test
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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

if [ -z "$OUTPUTFILE" ]; then
	export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../include/runtest.sh

BUG_INFO="1326373 - [sched] Update to 2.6.32-573.22.1 shows a mild increase in load average"
TEST_LIST=${TEST_LIST:-test}
PER_CASE_RUNTIME=${PER_CASE_RUNTIME:-300s}
PROCESS_CNT=${PROCESS_CNT:-$SCHED_NR_CPU}
SCHED_CMDLINE=${SCHED_CMDLINE:-}

AVG_DIFF=${AVG_DIFF:-0}

EL6_BASELINE=2.6.32-573.el6
# rhel7.6
EL7_BASELINE=3.10.0-957.el7
# rhel8 beta
EL8_BASELINE=4.18.0-305.el8
EL9_BASELINE=5.13.0-0.rc7.51.el9

function test_setup()
{
	test -f KERNEL_VR && return

	if uname -r | grep 'debug$'; then
		rstrnt-report-result "test debug kernel" SKIP
		exit 0
	fi

	rlPhaseStartSetup "Setup Test"
		rlLogInfo "Adding baseline: $BASELINE"
		sh ../../include/scripts/wget-kernel.sh --nvr $BASELINE --arch $(uname -m) ||
		rstrnt-report-result "download $BASELINE" "FAIL"
		# Firmware
		rlIsRHEL 6 && sh ../include/scripts/wget-kernel.sh --nvr $BASELINE --arch $(uname -m) --fw
		local kernel_vr=$(uname -r | grep -E ".*el[0-9]+" -o)
		[ -z "$kernel_vr" ] && kernel_vr=$(uname -r)
		local rpm_name=$(ls kernel*${BASELINE}.$(uname -m).rpm)
		local fw_rpm_name=$(ls kernel*${BASELINE}.$(uname -m).rpm)
		[ -z "$rpm_name" ] || [ -z "$fw_rpm_name" ] && rlDie "Can't install rpm since non-name!"
		rlIsRHEL 6 && rpm -ivh $fw_rpm_name
		# run the new kernel first.
		rlRun "grubby --set-default /boot/vmlinuz-${BASELINE}.$(uname -m)"
		rlRun "rpm -ivh $rpm_name --force"
		touch KERNEL_VR && echo "$kernel_vr" > KERNEL_VR
		rlRun -l "source_compile" || rlDie "processes compile failed"
		cp $SCHED_PROCESS_BIN/* .

	rlPhaseEnd
}

function test_clean()
{
	rlPhaseStartCleanup "Cleanup $(uname -r)"
		rlRun "killall life" 0-255
		rm -f life cpu_hog
	rlPhaseEnd
}


function test()
{
	rlPhaseStartTest "run-sleep 100us-10us"
	rlLogInfo "Case2: life 100us(run)-10us(sleep) duration 1h"
	rlLogInfo "Expect 63.5% more or less"
	local logfile=$(uname -r)-${FUNCNAME[0]}.100-10.loadavg
	for i in $(seq 1 $PROCESS_CNT); do
		rlRun "./life 1000 10 &"
	done

	rlRun "sleep $PER_CASE_RUNTIME" 0-255

	rlRun "sar -q 5 180 | tee $logfile"

	load_avg_sum $logfile

	rlFileSubmit $logfile
	rlRun "killall life" 0-255
	rlPhaseEnd
}


function testN()
{
	rlPhaseStartTest "run-sleep ${THIS_RUN}us-${THIS_SLEEP}us"
	rlLogInfo "CaseN: life ${THIS_RUN}us(run)-${THIS_SLEEP}us(sleep) duration 1h"
	# Fix me. not sure how to calculate now.
	rlLogInfo "Expect ?% more or less per cpu consumption"
	local logfile=$(uname -r)-${FUNCNAME[0]}.${THIS_RUN}-${THIS_SLEEP}.loadavg
	for i in $(seq 1 $PROCESS_CNT); do
		rlRun "./life $THIS_RUN $THIS_SLEEP &"
	done

	rlRun "sleep $PER_CASE_RUNTIME" 0-255

	rlRun "sar -q 5 100 | tee $logfile"
	load_avg_sum $logfile
	rlFileSubmit $logfile
	rlRun "killall life" 0-255
	rlPhaseEnd

}

function test_main()
{
	rlLogInfo "$BUG_INFO"

	if [ -n "$THIS_RUN" ] && [ -n "$THIS_SLEEP" ]; then
		rlPhaseStartTest "Schedule loadavg testN"
			killall life
			killall cpu_hog
			testN
		rlPhaseEnd
		return
	else
		rlLogInfo "Skip TestN as THIS_RUN and THIS_SLEEP test arg is ont defined."
	fi

	for t in $TEST_LIST; do
		rlPhaseStartTest "Schedule loadavg $t"
			echo "Before killing ...."
			ps -C life,cpu_hog
			killall life
			killall cpu_hog
			echo "After killing ...."
			ps -C life,cpu_hog
			$t
		rlPhaseEnd
		# let the loadavg calm down
		sleep 120
		echo "After 300seconds, we should calm down. check loadavg"
		for i in $(seq 1 5); do
			cat /proc/loadavg
			sleep 60s
		done
		echo
	done
}

rlJournalStart
	MAJOR_RELEASE=$(uname -r | sed -n 's/.*el\([0-9]\+\).*/\1/p')
	baseline_varname=EL${MAJOR_RELEASE}_BASELINE
	pegas=$(rpm -q --qf "%{sourcerpm}\n" -f /boot/vmlinuz-$(uname -r) | grep pegas)
	if [ -z "$MAJOR_RELEASE" ] || [ -z "${baseline_varname}" ]; then
		if [ -n "$pegas" ]; then
			rlLogWarning "Use $PEGAS_BASELINE as baseline, unknown $baseline_varname"
		fi
		baseline_varname=PEGAS_BASELINE
	fi
	[ -z "$BASELINE" ] && BASELINE=${!baseline_varname}
	test_setup
	if test -f reboot_$(cat KERNEL_VR); then
		echo "Test Done, rebooted to $(uname -r)"
		test_clean
	elif test -f reboot_${BASELINE}; then
		grubby --set-default /boot/vmlinuz-$(cat KERNEL_VR).$(uname -m) ||
			echo "Set back to $(cat KERNEL_VR) failed" && exit
		echo "Set back to $(cat KERNEL_VR), default kernel is:"
		grubby --default-kerel
		test_main
		# Reboot to baseline, to get the baseline result.
		touch reboot_$(cat KERNEL_VR)
		rstrnt-reboot
	else
		# Loadavg of the Test kernel.
		test_main
		# Reboot to baseline, to get the baseline result.
		touch reboot_${BASELINE}
		((AVG_DIFF)) && rstrnt-reboot
	fi
rlJournalEnd
rlJournalPrintText

