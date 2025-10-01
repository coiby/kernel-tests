#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/clevis/Sanity/pin-tpm2
#   Description: Test the TPM2.0 functionality of Clevis
#   Author: Martin Zeleny <mzeleny@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
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

PACKAGE="clevis"
FMT="%{name}-%{version}-%{release}\n"

rlJournalStart
	rlPhaseStartSetup
		rlAssertRpm ${PACKAGE}
		packageVersion=$(rpm -q ${PACKAGE} --qf ${FMT})
		rlTestVersion "${packageVersion}" '>=' 'clevis-7-6' || rlDie "Tested functionality is not in old version ${packageVersion}"

		TmpDir=$(mktemp -d)
		rlRun "pushd ${TmpDir}"
	rlPhaseEnd

	rlPhaseStart FAIL "PCR Binding Testing, decryption after state change should fail"
		if [ ! -e /var/tmp/clevis_pcr.flag ]; then
			# if pcr was not extended yet, run initial stage of testing
			rlRun "echo \"PCR-bound secret\" > /var/tmp/pcr_plain.txt"
			rlRun "clevis encrypt tpm2 '{\"pcr_bank\":\"sha256\",\"pcr_ids\":\"16\"}' < /var/tmp/pcr_plain.txt > /var/tmp/pcr_cipher.jwe" 0 "PCR bind the secret message with tpm encryption"
			rlRun "clevis decrypt < /var/tmp/pcr_cipher.jwe > /var/tmp/pcr_decrypted.txt" 0 "Decrypt the cipher and store it"
			rlRun "diff /var/tmp/pcr_decrypted.txt /var/tmp/pcr_plain.txt"
			rlRun "tpm2_pcrextend 16:sha256=$(printf \"%064x\" 0)" 0 "Extend the PCR, thus changing its state"
			rlRun "clevis decrypt < /var/tmp/pcr_cipher.jwe" 1 "A post PCR state change decrypt should fail"
			rlRun "touch /var/tmp/clevis_pcr.flag" 0 "Create pcr extension reboot flag"
			rlRun "rstrnt-reboot" 0 "Reboot the machine, PCR extension is volatile"
		else
			rlRun "clevis decrypt < /var/tmp/pcr_cipher.jwe > /var/tmp/pcr_decrypted_post_reboot.txt" 0 "PCR extension should not persist"
			rlRun "diff /var/tmp/pcr_decrypted_post_reboot.txt /var/tmp/pcr_plain.txt" 0 "Decrypt after reboot should succeed"
			rlRun "rm -fr /var/tmp/clevis_pcr.flag /var/tmp/pcr_*"
		fi
	rlPhaseEnd

	rlPhaseStartTest
		rlRun "tpm2_clear" 0 "Clear TPM2.0 chip before testing"
		rlRun "sleep 1"
		rlRun "echo 'secret msg' > PT" 0 "Create plaintext file with test to encrypt"
		rlRun "clevis encrypt tpm2 '{}' < PT > JWE" 0 "Encrypt plaintext using TPM2.0"
		rlRun "cat JWE"

		rlRun "clevis decrypt < JWE > OUTPUT"
		rlRun "cat OUTPUT"
		rlAssertNotDiffer PT OUTPUT
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "popd"
		rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd

