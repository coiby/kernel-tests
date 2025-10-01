#!/bin/bash
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

. /usr/share/beakerlib/beakerlib.sh

MODULE_PATH="$(find / -name libtpm2_pkcs11.so)"
TOKEN_LABEL="newtoken"
USER_PIN="1234"
SO_PIN="12345678"
RSA_KEY_LABEL="rsa_key"

rlJournalStart
	# first start tpm2-abrmd, all calls need it
	rlPhaseStartSetup

	# Detect RHEL major to know what we can do
		if rlIsRHEL "<9"; then
			rlRun "exit 0" 0 "Old RHEL version detected, skipping testing"
		fi


		rlRun "packageVersion=$(rpm -q ${PACKAGE} --qf ${FMT})"
		rlRun "udevadm trigger --action=change"

		# start tpm2-abrmd daemon
		if ! systemctl status tpm2-abrmd > /dev/null
		then
			rlRun "systemctl start tpm2-abrmd" 0 "starting tpm2-abrmd"
		fi
		sleep 1
	rlPhaseEnd

	rlPhaseStart FAIL "Initialization and token management"
		rlRun "tpm2_ptool init > init.out" 0 "Initializing the PKCS#11 store"
		ID=$(cat init.out | grep "^id:" | awk '{print $2}')
		rlRun "tpm2_ptool addtoken --label $TOKEN_LABEL --sopin $SO_PIN --userpin $USER_PIN --pid $ID" 0 "Creating a new token"
		rlRun "pkcs11-tool --module $MODULE_PATH -L | grep $TOKEN_LABEL" 0 "Verifying token visibility"
	rlPhaseEnd

	rlPhaseStart FAIL "Testing the key and object lifecycle"
		rlRun "pkcs11-tool --module $MODULE_PATH --login --pin $USER_PIN --keypairgen --key-type rsa:2048 --label $RSA_KEY_LABEL --usage-sign" 0 "Generating an RSA key pair"
		# Verifying that RSA key objects are listed
		rlRun "pkcs11-tool --module $MODULE_PATH --login --pin $USER_PIN -O | grep -A2 \"Private Key Object; RSA\" | grep $RSA_KEY_LABEL"
		rlRun "pkcs11-tool --module $MODULE_PATH --login --pin $USER_PIN -O | grep -A2 \"Public Key Object; RSA\" | grep $RSA_KEY_LABEL"
	rlPhaseEnd

	rlPhaseStart FAIL "RSA signing and signature verification"
		rlRun "echo rsa_data > rsa_data.txt"
		rlRun "pkcs11-tool --module $MODULE_PATH --login --pin $USER_PIN --sign --label $RSA_KEY_LABEL --mechanism SHA256-RSA-PKCS -i rsa_data.txt -o rsa_data.sig" 0 "Performing RSA signing"
		rlRun "pkcs11-tool --module $MODULE_PATH --login --pin $USER_PIN --read-object --label $RSA_KEY_LABEL --type pubkey -o pubkey.der" 0 "Extracting the public key from the TPM"
		rlRun "openssl rsa -pubin -inform DER -in pubkey.der -outform PEM -out pubkey.pem" 0 "Binary to text conversion of the public key"
		rlRun "openssl dgst -sha256 -verify pubkey.pem -signature rsa_data.sig rsa_data.txt | grep \"Verified OK\"" 0 "Checks for signature authenticity"
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "tpm2_ptool rmtoken --label $TOKEN_LABEL"
		rlRun "for handle in \$(tpm2_getcap handles-persistent | grep -o '0x[0-9A-Fa-f]*'); do tpm2_evictcontrol -C o -c \$handle; done" 0 "Clear all persistent handles"
		rlRun "rm -fr rsa_data* *.pem *.der init.out"
	rlPhaseEnd
rlJournalEnd
