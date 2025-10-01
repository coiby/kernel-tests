#!/bin/bash
# vim: ai si dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/security/crypto/tmp/tpm2-tools
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

COM_OPTS="-T tabrmd"
HASH_OPTS="-C n"

rlJournalStart
	# first start tpm2-abrmd, all calls need it
	rlPhaseStartSetup

		# Detect RHEL major to know what we can do
		if rlIsRHEL "<8"; then
				COM_OPTS=""
				HASH_OPTS=""
				rlLogInfo "Old RHEL version detected, testing limited"
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

	rlPhaseStart FAIL "Presence"
		if rlIsRHEL ">7"; then
			rlRun "tpm2_pcrread $COM_OPTS"
			COUNT=`tpm2_pcrread $COM_OPTS | grep '^ \+[0-9]\+ *: ' | wc -l`
			rlAssertGreaterOrEqual "24 PCRS" "$COUNT" 24
		fi
		rlAssertExists "/dev/tpm0"
	rlPhaseEnd

	rlPhaseStart FAIL "Query for properties and supported algorithms"
		rlRun "tpm2_getcap properties-fixed" 0 "Vendor info and fixed properties"
		rlRun "tpm2_getcap properties-variable" 0 "Mutable properties"
		rlRun "tpm2_getcap algorithms" 0 "Supported cryptographic algorithms"
	rlPhaseEnd

	if tpm2_getcap algorithms | grep -q hmac; then
		rlPhaseStart FAIL "Testing TPM-resident key for keyed hashing (HMAC)"
			rlRun "tpm2_createprimary -Q -C o -c primary.ctx" 0 "Create primary key to use with HMAC"
			rlRun "tpm2_create -Q -C primary.ctx -G hmac -c hmac.ctx" 0 " Create HMAC key under primary key"
			rlRun "echo \"test data\" | tpm2_hmac -Q -c hmac.ctx -o hmac.out" 0 "Generate HMAC"
		rlPhaseEnd
	fi

	rlPhaseStart FAIL "Tests creating, loading, and using a key within the TPM"
		rlRun "tpm2_createprimary -Q -C o -g sha256 -G rsa -c primary.ctx" 0 "Creates root key"
		rlRun "tpm2_create -Q -C primary.ctx -g sha256 -G rsa -u key.pub -r key.priv" 0 "Creates RSA key under root key"
		rlRun "tpm2_load -Q -C primary.ctx -u key.pub -r key.priv -c key.ctx" 0 "Load key into the TPM"
		rlRun "echo \"secret tpm data\" > data.txt" 0 "Creates sample data"
		rlRun "tpm2_rsaencrypt -Q -c key.ctx -o data.encrypted data.txt" 0 "RSA encryption using TPM"
		rlRun "tpm2_rsadecrypt -Q -c key.ctx -o data.decrypted data.encrypted" 0 "Decrypt using TPM"
		rlRun "diff data.decrypted data.txt" 0 "Check that the decrypted data matches original"
		rlRun "tpm2_flushcontext -l" 0 "Remove all RSA session contexts from TPM chip"
	rlPhaseEnd

	rlPhaseStart FAIL "Functionality"
		if rlIsRHEL ">7"; then
			rlRun "tpm2_nvreadpublic $COM_OPTS"
		fi
		DATA=`mktemp`
		rlRun "tpm2_getrandom $COM_OPTS -o $DATA 20" 0 "random number generator"
		COUNT=`wc -c "$DATA" | cut -d\  -f1`
		rlAssertEquals "random number count" "$COUNT" 20
		rlRun "tpm2_selftest -f" 0 "Running internal self-tests"
		HASHED=`mktemp -u`
		TICKET=`mktemp -u`
		rlRun "tpm2_hash $COM_OPTS $HASH_OPTS -g 0x0004 -o $HASHED -t $TICKET $DATA" 0 "hashing"
		rm -f $DATA $HASHED $TICKET

		# extending PCRs, not available in RHEL7
		if rlIsRHEL ">7"; then
			NUM_SHA1=`tpm2_pcrread $COM_OPTS sha1 2>/dev/null | wc -l`
			NUM_SHA256=`tpm2_pcrread $COM_OPTS sha256 2>/dev/null | wc -l`
			#NUM_SHA512=`tpm2_pcrread $COM_OPTS sha512 2>/dev/null | wc -l`
			#NUM_SM3_256=`tpm2_pcrread $COM_OPTS sm3_256 2>/dev/null | wc -l`
			ORIGINAL=`tpm2_pcrread $COM_OPTS | grep ' 4 *:' | head -n 1`
			if [ $NUM_SHA1 -gt 1 ]
			then
				rlRun "tpm2_pcrextend $COM_OPTS 4:sha1=f1d2d2f924e986ac86fdf7b36c94bcdf32beec15" 0 "extending PCR SHA1"
			else
				if [ $NUM_SHA256 -gt 1 ]
				then
					rlRun "tpm2_pcrextend $COM_OPTS 4:sha256=7FE387F3E0AD249763107E6BCD9B17F5CCE2002AEE4093C7D270481A8ACC0BE5" 0 "extending PCR SHA256"
				else
					rlFail "Neither SHA1 nor SHA256 list in tpm2_pcrread"
				fi
			fi
			MODIFIED=`tpm2_pcrread $COM_OPTS | grep ' 4 *:' | head -n 1`
			rlAssertNotEquals "PCR value changed" "$ORIGINAL" "$MODIFIED"
		fi

		# decoding result codes
		COUNT=`tpm2_rc_decode 0x9a2 | grep "authorization failure" | wc -l`
		rlAssertEquals "tpm2_rc_decode 0x9a2 -> authorization failure" "$COUNT" 1

		# encoding TSS keys
		if [ -x /usr/bin/tpm2_encodeobject ]
		then
			rlRun "tpm2_createprimary -c primary.ctx" 0 "Creating primary context"
			rlRun "tpm2_create -C primary.ctx -u key.pub -r key.priv -f pem -o pub.pem" 0 "Creating private/public keys"
			rlRun "tpm2_encodeobject -C primary.ctx -u key.pub -r key.priv -o priv.pem" 0 "Encoding private key"
			rlRun "tpm2_encodeobject -C primary.ctx -u key.pub -r key.pub -o pub.pem" 0 "Encoding public key"
			rm -f key.priv key.pub primary.ctx priv.pem pub.pem
		fi
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "rm -fr primary.ctx hmac.*" 0 "Removes HMAC testing files"
		rlRun "rm -fr primary.ctx key.pub key.priv key.ctx data.txt data.encrypted data.decrypted" 0 "Removes full TPM lifecycle RSA files"
	rlPhaseEnd

	rlJournalPrintText
rlJournalEnd
