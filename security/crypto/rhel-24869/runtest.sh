#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/crypto/rhel-24869
#   Description: Test for rhel-24869 (Note: test should be run under FIPS mode)
#   Author: Dennis Li <denli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1
. ../enable_fips/lib.sh || exit 1

devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel

		if rlIsRHEL "< 8.8"; then
			echo "[SKIP] Test requires RHEL 8.8+"
			rstrnt-report-result $RSTRNT_TASKNAME SKIP
			exit 0
		fi

		rlRun "fipsIsEnabled" 0 && rlPass "FIPS mode is enabled" && fips_enabled=0
		if [ ! ${fips_enabled} ]; then
			echo "[SKIP] Test should run under FIPS mode"
			rstrnt-report-result $RSTRNT_TASKNAME SKIP
			exit 0
		fi

		rlRun "yum install -y $devel_pkg"
		rlRun "pushd ./source"
		rllog "Compiling test kernel module"
		rlRun "make" 0
	rlPhaseEnd

	rlPhaseStartTest "Loading testing module"
		rlRun -l "insmod test_rsa_set_key.ko" 0
		if [ $? -eq 0 ]; then
			rlPass "Test PASS"
			rlRun "rmmod test_rsa_set_key.ko"
		else
			rlFail "Test Fail, please check dmesg log for expected results"
		fi
	rlPhaseEnd

	rlPhaseStartCleanup
		rlFileSubmit dmesg
		rlRun "dmesg -c"
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText