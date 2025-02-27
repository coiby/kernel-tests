#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/kmemleak
#   Description: Check that kmemleak is working (debug kernel)
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

FLAG_FILE=/mnt/reboot_kmemleak_enable

# Leave the leak data in /sys/kernel/debug/kmemleak without cleanup, used as a
# input leak data for verifying that /kernel/general/memory/kmemleak is working
# correctly.
RESERVE_LEAK=${RESERVE_LEAK:-0}
RESERVE_LEAK_REBOOT=${RESERVE_LEAK_REBOOT:-0}

LEAK_TRACE_FILE=/sys/kernel/debug/kmemleak

function enable_kmemleak()
{
	if test -f $FLAG_FILE; then
		rlAssertGrep "kmemleak=on" /proc/cmdline
		return
	fi

	if grep 'kmemleak=on' /proc/cmdline && ! test -f $FLAG_FILE; then
		echo "kmemleak is enabled by default"
		touch $FLAG_FILE
		echo reserve > $FLAG_FILE
		return
	fi

	grubby --args kmemleak=on --update-kernel DEFAULT
	uname -r | grep -q s390x && zipl
	touch $FLAG_FILE
	rstrnt-reboot
}

function reset_kmemleak()
{
	if test -f $FLAG_FILE; then
		if grep reserve $FLAG_FILE; then # kmemleak is enabled(There's a kmemleak=on) in kernel cmdline by default, don't need to disable it after test finished.
			echo "reserve kmemleak=on in cmdline"
			echo finish >> $FLAG_FILE
			if [ "$RESERVE_LEAK_REBOOT" = 1 ]; then
				[ "$result" = PASS ] || rlDie "Failed to generate kmemleak, can't be used as leak input for /kernel/general/memory/kmemleak"
				rstrnt-reboot
			elif [ "$RESERVE_LEAK" = "1" ]; then
				[ "$result" = PASS ] || rlDie "Failed to generate kmemleak, can't be used as leak input for /kernel/general/memory/kmemleak"
			else
				[ "$result" = PASS ] && rlRun "echo clear > $LEAK_TRACE_FILE"
			fi
			rm -f $FLAG_FILE
		else
			grubby --remove-args kmemleak=on --update-kernel DEFAULT
			uname -r | grep s390x -q && zipl
			echo finish > $FLAG_FILE
			rstrnt-reboot
		fi
	fi
}

function run_kmemleak_test()
{
	if test -f $FLAG_FILE && grep -q finish $FLAG_FILE && echo "kmemleak test finished"; then
		grep -q reserve $FLAG_FILE || rlAssertNotGrep 'kmemleak=on' /proc/cmdline
		rm -f $FLAG_FILE
		return
	fi

	# Setup
	rlPhaseStartSetup

	if ! [[ "`uname -r`" =~ "debug" ]]; then
		rlLogInfo "Skip Test! kmemleak is only enabled for debug kernels."
		rlPhaseEnd
		return
	fi

	[ "$RESERVE_LEAK" = 1 ] && [ "$RESERVE_LEAK_REBOOT" = 1 ] && rlReport "ignore RESERVE_LEAK=1" WARN

	enable_kmemleak

	# Install kernel-debug-devel for the version of the running kernel
	uname -r | grep rt -q && kname=kernel-rt
	kname=${kname:-kernel}
	rpm -q ${kname}-debug-devel | grep ${kname}-debug-devel-$(uname -r|sed 's/[.+]debug//') || sh ../../../include/scripts/wget-kernel.sh --running --devel -i
	rpm -q elfutils-libelf-devel || dnf install -y elfutils-libelf-devel

	pushd kmemleak_test
	unset ARCH
	rlRun "make" || rlDie "compile test module"
	popd

	rlPhaseEnd

	# Test
	rlPhaseStartTest

	dmesg -C
	pushd kmemleak_test
	rlRun "insmod kmemleak_test.ko"
	popd

	result=FAIL
	# shellcheck disable=SC2034
	for i in $(seq 1 5); do
		rlRun "echo scan > $LEAK_TRACE_FILE"
		grep insmod $LEAK_TRACE_FILE &&
		egrep "unreferenced.*size [0-9]+" $LEAK_TRACE_FILE &&
		egrep "[0-9a-f]+.*do_init_module" $LEAK_TRACE_FILE &&
		result=PASS && break
	done
	rlRun "cat $LEAK_TRACE_FILE" -l
	rstrnt-report-result slub_leak $result

	if [ "$result" = PASS ]; then
		obj_addr=$(awk '/unreferenced object/ {print $3; exit(0)}' $LEAK_TRACE_FILE)
		rlRun "echo dump=$obj_addr > $LEAK_TRACE_FILE"
		rlRun "dmesg | grep \"Object $obj_addr\""
	fi

	rlPhaseEnd

	# Cleanup
	rlPhaseStartCleanup

	reset_kmemleak
	rmmod kmemleak_test
	pushd kmemleak_test
	make clean
	popd

	rlPhaseEnd
}

rlJournalStart
run_kmemleak_test
rlJournalPrintText
rlJournalEnd
