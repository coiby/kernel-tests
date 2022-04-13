#!/usr/bin/bash

#  Include the BeakerLib environment
# shellcheck disable=SC1091
. /usr/share/beakerlib/beakerlib.sh

# Set the full test name
# shellcheck disable=SC2034
TEST="upt-smoke-tests/fail"


rlJournalStart
    # Setup phase
    rlPhaseStartSetup
        rlLog "Running our setup stage"
        rlRun "echo 'Running setup stage'"
    rlPhaseEnd

    # Test 1
    rlPhaseStartTest First_test
        rlLog "Running our first smoke test"
        rlRun "echo 'Running our first smoke test'"
    rlPhaseEnd

    # Test 2
    rlPhaseStartTest Second_test
        rlLog "Running our second smoke test setting FAIL in restraint report"
        rlRun "echo 'Running our second smoke test'"
        rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL
    rlPhaseEnd

    # Test 3
    rlPhaseStartTest Third_test
        rlLog "Running our third smoke test setting"
        rlRun "echo 'Running our third smoke test'"
    rlPhaseEnd

    # Cleanup phase
    rlPhaseStartCleanup
        rlLog "Running our clean stage"
        rlRun "echo 'Running clean stage'"
    rlPhaseEnd
rlJournalEnd

# Print the test report
rlJournalPrintText
