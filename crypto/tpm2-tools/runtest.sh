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

dnf install -y beakerlib

# Source the common test script helpers
. /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh


SECTION=""
rlJournalStart
	# first start tpm2-abrmd, all calls need it
	rlPhaseStartSetup
		rlRun "dnf install -y trousers tpm-tools"
		rlRun "udevadm trigger --action=change"
		if ! systemctl status tpm2-abrmd > /dev/null
		then
			rlRun "systemctl start tpm2-abrmd" 0 "starting tpm2-abrmd"
		fi
		#rlRun "screen -S tpm2-abrmd -d -m tpm2-abrmd" 0 "starting tpm2-abrmd"
		sleep 1
	rlPhaseEnd

	rlPhaseStart FAIL "Presence"
		rlRun "tpm2_pcrread -T tabrmd"
		COUNT=`tpm2_pcrread -T tabrmd | grep '^ \+[0-9]\+ \+: ' | wc -l`
		rlAssertGreaterOrEqual "24 PCRS" "$COUNT" 24
		rlAssertExists "/dev/tpm0"
	rlPhaseEnd

	rlPhaseStart FAIL "Functionality"
		rlRun "tpm2_nvreadpublic -T tabrmd"
		DATA=`mktemp`
		rlRun "tpm2_getrandom -T tabrmd -o $DATA 20" 0 "random number generator"
		COUNT=`wc -c "$DATA" | cut -d\  -f1`
		rlAssertEquals "random number count" "$COUNT" 20
		HASHED=`mktemp -u`
		TICKET=`mktemp -u`
		rlRun "tpm2_hash -T tabrmd -C n -g 0x0004 -o $HASHED -t $TICKET $DATA" 0 "hashing"
		rm -f $DATA $HASHED $TICKET

		# need to define persistent objects first
		#rlRun "tpm2_listpersistent"
		#COUNT=`tpm2_listpersistent | grep key-alg | wc -l`
		#rlAssertGreater "persistent objects defined" "$COUNT" 0

		ORIGINAL=`tpm2_pcrread -T tabrmd | grep ' 4  :' | head -n 1`
		rlRun "tpm2_pcrextend -T tabrmd 4:sha1=f1d2d2f924e986ac86fdf7b36c94bcdf32beec15" 0 "extending PCR"
		MODIFIED=`tpm2_pcrread -T tabrmd | grep ' 4  :' | head -n 1`
		rlAssertNotEquals "PCR value changed" "$ORIGINAL" "$MODIFIED"

		COUNT=`tpm2_rc_decode 0x9a2 | grep "authorization failure" | wc -l`
		rlAssertEquals "tpm2_rc_decode 0x9a2 -> authorization failure" "$COUNT" 1
	rlPhaseEnd

	rlPhaseStart FAIL "Data RW"
		
	rlPhaseEnd

	# stop resourcemgr
	rlPhaseStartCleanup
		#rlRun "screen -X -S tpm2-abrmd quit" 0 "stopping tpm2-abrmd"
	rlPhaseEnd
	
	rlJournalPrintText
rlJournalEnd

