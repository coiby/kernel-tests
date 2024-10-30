#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
rlJournalStart
	rlPhaseStartSetup "Prepare nftables upstream binary"
		if [[ ! -x ./iptables/install/sbin/xtables-nft-multi ]];then
			rlRun "bash -x full_rebuild.sh"
		fi
		rlRun "dnf -y install kernel-modules-extra-$(uname -r)"
		rlRun "dnf -y install valgrind"
	rlPhaseEnd

	rlPhaseStartTest "iptables/tests/shell"
		rlRun "pushd iptables/iptables/tests/shell"
		rlRun "bash ./run-tests.sh"
		rlRun "popd"
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd

	rlJournalPrintText
rlJournalEnd

