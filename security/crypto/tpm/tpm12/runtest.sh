#!/bin/bash
# vim: ai si dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/crypto/tmp/tpmtest
#   Description: TPM2-TSS testsuite wrapper
#   Author: Vilem Marsik <vmarsik@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh


SECTION=""
CONTENT="testcontent$$"
rlJournalStart
	# first start tcsd, all calls need it
	rlPhaseStartSetup
		rlRun "service tcsd start" 0 "starting tcsd"
		sleep 1
	rlPhaseEnd

	# just basic tests
	rlPhaseStart FAIL "Basic tests"
		rlRun tpm_version 0 "TPM version"
		rlRun tpm_selftest 0 "TPM selftest"
		rlRun "tpm_getpubek -z" 0 "get public key"
		rlRun tpm_nvinfo 0 "nvinfo"
	rlPhaseEnd

	# get ownership
	rlPhaseStart WARN "Take ownership"
		rlRun "tpm_takeownership -y -z" 0 "Take TPM ownership"
	rlPhaseEnd

	# defining, writing, reading and releasing values
	rlPhaseStart FAIL "Data RW"
		if tpm_nvinfo | grep '(2)' >/dev/null
		then
			rlRun "tpm_nvrelease -i 2 -y" 0 "index 2 already defined, releasing"
		fi
		if tpm_nvinfo | grep '(3)' >/dev/null
		then
			rlRun "tpm_nvrelease -i 3 -y" 0 "index 3 already defined, releasing"
		fi

		rlRun "tpm_nvdefine -l debug -i 2 -s 32 -p 'AUTHREAD|AUTHWRITE' -a nvpass -o test -y" 0 "define index 2"
		rlRun "tpm_nvdefine -l debug -i 3 -s 32 -p 'OWNERREAD|OWNERWRITE' -o test -y" 0 "define index 3"
		rlRun "tpm_nvwrite -l debug -i 3 -d $CONTENT -z" 0 "write"
		rlRun "tpm_nvread -l debug -i 3 -z | grep $CONTENT" 0 "read"
		COUNT=`tpm_nvinfo | grep '([23])' | wc -l`
		rlLogInfo "tpm_nvinfo found $COUNT defined keys"
		rlAssertEquals "keys defined count" $COUNT 2
		rlRun "tpm_nvrelease -i 2 -y" 0 "release index 2"
		rlRun "tpm_nvrelease -i 3 -y" 0 "release index 3"
		COUNT=`tpm_nvinfo | grep '([23])' | wc -l`
		rlAssert0 "both keys released" $COUNT
	rlPhaseEnd

	rlPhaseStart FAIL "(Un)Sealing"
		DIR=`mktemp -d`
		pushd "$DIR"
			echo "$CONTENT" > secret
			rlRun "tpm_sealdata -i secret -o sealed_secret -z" 0 "Sealing"
			rlAssertExists sealed_secret
			rlRun "tpm_unsealdata -i sealed_secret -o unsealed_secret -z" 0 "Unsealing"
			rlAssertExists unsealed_secret
			rlAssertNotDiffer secret unsealed_secret
		popd
		rm -rf "$DIR"
	rlPhaseEnd

	# stop resourcemgr
	rlPhaseStartCleanup
		rlRun "service tcsd stop" 0 "stopping tcsd"
	rlPhaseEnd

	rlJournalPrintText
rlJournalEnd
