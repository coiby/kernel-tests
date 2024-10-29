#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
rlJournalStart
	rlPhaseStartSetup "Prepare nftables upstream binary"
		rlRun "rpm -q socat || dnf -y install socat"
		if [[ ! -x nftables/src/nft ]];then
			rlRun "bash -x full_rebuild.sh"
		fi
	rlPhaseEnd

	rlPhaseStartTest "nftables/tests/shell"
		rlRun "pushd nftables/tests/shell"
		# If tests are executed in parallel, a tainted kernel can cause other reports to show as TAINTED,
		# making it unclear which test originally lead to taint
		rlRun "NFT_TEST_JOBS=1 bash run-tests.sh"
		rlRun "popd"
	rlPhaseEnd

	rlPhaseStartTest "nftables/tests/monitor"
		rlRun "pushd nftables/tests/monitor"
		rlRun "./run-tests.sh -d"
		rlRun "popd"
	rlPhaseEnd

	rlPhaseStartTest "nftables/tests/py"
		rlRun "pushd nftables/tests/py"
		rlRun "python nft-test.py"
		rlRun "popd"
	rlPhaseEnd

	rlPhaseStartTest "nftables/tests/json_echo"
		rlRun "pushd nftables/tests/json_echo"
		rlRun "python run-test.py"
		rlRun "popd"
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd

	rlJournalPrintText
rlJournalEnd

