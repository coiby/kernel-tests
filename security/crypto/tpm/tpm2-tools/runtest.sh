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

PACKAGES="beakerlib tpm2-tools tpm2-abrmd perl"
if which dnf 2>/dev/null >/dev/null
then
	dnf install -y $PACKAGES
else
	yum install -y $PACKAGES
fi

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh

RHEL_MAJOR=`perl -ne 'print $1 if $_=~/release\s*(\d+)/' /etc/redhat-release`
COM_OPTS="-T tabrmd"
HASH_OPTS="-C n"

rlJournalStart
	# first start tpm2-abrmd, all calls need it
	rlPhaseStartSetup

		# Detect RHEL major to know what we can do
		if [ -z "$RHEL_MAJOR" ]
		then
			rlLogWarning "Could not detect RHEL version"
		elif [ "$RHEL_MAJOR" -eq "7" ]
		then
				COM_OPTS=""
				HASH_OPTS=""
				rlLogInfo "Old RHEL version $RHEL_MAJOR detected, testing limited"
		else
			rlLogInfo "Detected RHEL version $RHEL_MAJOR"
		fi


		rlRun "packageVersion=$(rpm -q ${PACKAGE} --qf ${FMT})"
		rlRun "udevadm trigger --action=change"

		# start tpm2-abrmd daemon
		if ! systemctl status tpm2-abrmd > /dev/null
		then
			rlRun "systemctl start tpm2-abrmd" 0 "starting tpm2-abrmd"
		fi
		#rlRun "screen -S tpm2-abrmd -d -m tpm2-abrmd" 0 "starting tpm2-abrmd"
		sleep 1
	rlPhaseEnd

	rlPhaseStart FAIL "Presence"
		if [ $RHEL_MAJOR -gt 7 ]
		then
			rlRun "tpm2_pcrread $COM_OPTS"
			COUNT=`tpm2_pcrread $COM_OPTS | grep '^ \+[0-9]\+ *: ' | wc -l`
			rlAssertGreaterOrEqual "24 PCRS" "$COUNT" 24
		fi
		rlAssertExists "/dev/tpm0"
	rlPhaseEnd

	rlPhaseStart FAIL "Functionality"
		if [ $RHEL_MAJOR -gt 7 ]
		then
			rlRun "tpm2_nvreadpublic $COM_OPTS"
		fi
		DATA=`mktemp`
		rlRun "tpm2_getrandom $COM_OPTS -o $DATA 20" 0 "random number generator"
		COUNT=`wc -c "$DATA" | cut -d\  -f1`
		rlAssertEquals "random number count" "$COUNT" 20
		HASHED=`mktemp -u`
		TICKET=`mktemp -u`
		rlRun "tpm2_hash $COM_OPTS $HASH_OPTS -g 0x0004 -o $HASHED -t $TICKET $DATA" 0 "hashing"
		rm -f $DATA $HASHED $TICKET

		# need to define persistent objects first
		#rlRun "tpm2_listpersistent"
		#COUNT=`tpm2_listpersistent | grep key-alg | wc -l`
		#rlAssertGreater "persistent objects defined" "$COUNT" 0

		# extending PCRs, not available in RHEL7
		if [ $RHEL_MAJOR -gt 7 ]
		then
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

	# stop resourcemgr
	#rlPhaseStartCleanup
		#rlRun "screen -X -S tpm2-abrmd quit" 0 "stopping tpm2-abrmd"
	#rlPhaseEnd

	rlJournalPrintText
rlJournalEnd

