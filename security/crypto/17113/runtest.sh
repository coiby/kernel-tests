#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/crypto/17113
#   Description: Test for rhel17113 (Note: test is to verify that crypto asy decryption function not avalible in kernel to prevent exploration)
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

devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel
		rlRun "yum install -y gcc $devel_pkg"
		rlRun "pushd ./source"
		rllog "Compiling test kernel module"
		rlRun "make" 0
	rlPhaseEnd

	rlPhaseStartTest "Calling crypto_akcipher_decrypt function, expecting function not available"
		rlRun -l "insmod test_rsa_decrypt.ko" 1
		if [ $? -eq 1 ]; then
			rlPass "RSA decrypt function not available"
		else
			rlFail "RSA decrypt function available, system might expose to side-channel leakage"
			rlRun "rmmod test_rsa_decrypt"
		fi
	rlPhaseEnd

	rlPhaseStartCleanup
		rlFileSubmit dmesg
		rlRun "dmesg -c"
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText