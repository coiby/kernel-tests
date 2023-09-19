#!/usr/bin/bash

#  Include the BeakerLib environment
# shellcheck disable=SC1091
. /usr/share/beakerlib/beakerlib.sh

# Set the full test name
# shellcheck disable=SC2034
TEST="upt-smoke-tests/timeout"


rlJournalStart
    # Setup phase
    rlPhaseStartSetup
        rlLog "Running our setup stage"
        rlRun "echo 'Running setup stage'"
    rlPhaseEnd

    # Test 1
    rlPhaseStartTest First_test
        rlLog "Sleep 60, the test will be aborted after 10 seconds"
        rlRun "sleep 60"
    rlPhaseEnd

    # Cleanup phase
    rlPhaseStartCleanup
        rlLog "Running our clean stage"
        rlRun "echo 'Running clean stage'"
    rlPhaseEnd
rlJournalEnd

# Print the test report
rlJournalPrintText
