#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   general/locking/preempt_spinlock
#   Description: verify spinlock could be preempted in PREEMPT_RT
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../../automotive/include/rhivos.sh
declare -F kernel_automotive

# for ostree support
if stat /run/ostree-booted > /dev/null 2>&1; then
	CONFIG=/usr/lib/ostree-boot/config-$(uname -r)
else
	CONFIG=/boot/config-$(uname -r)
fi

rlJournalStart
	if ! grep 'CONFIG_PREEMPT_RT=y' $CONFIG; then
		rstrnt-report-result "CONFIG_PREEMPT_RT not enabled" SKIP
		rlPhaseEnd
		exit 0
	fi

	rlPhaseStartSetup
		if ! kernel_automotive; then
			kname="$(rpm -qf --qf "%{name}\n" /boot/vmlinuz-$(uname -r) | sed 's/-core//g')"
			kversion="$(rpm -qf --qf "%{version}\n" /boot/vmlinuz-$(uname -r))"
			krelease="$(rpm -qf --qf "%{release}\n" /boot/vmlinuz-$(uname -r))"
			rpm -q "${kname}-devel-${kversion}-${krelease}" || rlRpmInstall "${kname}-devel" "$kversion" "$krelease" "$(uname -m)"
			rpm -q "${kname}-devel-${kversion}-${krelease}" || rlDie "no ${kname}-devel package available"
		else
			install_kernel_automotive_devel || { rstrnt-report-result "${kname}-devel" FAIL; exit 1; }
		fi
	rlPhaseEnd

	rlPhaseStartTest
		pushd preempt_spinlock
		rlRun "make" 0 "compile the preempt_spinlock.ko" || { rstrnt-report-result "compile preempt_spinlock.ko" FAIL; exit 1; }
		popd

		dmesg -C
		rlRun "insmod preempt_spinlock/preempt_spinlock.ko"
		dmesg | tee test_dmesg.txt
		rlFileSubmit test_dmesg.txt
		rlRun "grep PASS test_dmesg.txt" 0 "The module should report PASS in dmesg"
	rlPhaseEnd

	rlPhaseStartCleanup
		pushd preempt_spinlock
		rlRun "make clean"
		popd
		rmmod preempt_spinlock
		rm -f test_dmesg.txt
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

