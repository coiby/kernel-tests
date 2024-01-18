#!/bin/bash

set -e

. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

	rlPhaseStartTest
		virsh list
		virsh guestinfo GuestOne --os
		virsh shutdown GuestOne
		sleep 30

		if virsh list --all | grep 'GuestOne.*shut off'
		then
			rstrnt-report-result "misc/guest-poweroff" PASS
		else
			rstrnt-report-result "misc/guest-poweroff" FAIL
		fi
	rlPhaseEnd

rlJournalPrintText
rlJournalEnd
