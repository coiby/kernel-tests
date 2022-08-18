#!/bin/bash
# Include beakerlib
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartSetup
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "rpm -q trace-cmd || rpm-ostree install -A --idempotent --allow-inactive trace-cmd"
        else
            rlRun "rpm -q trace-cmd || yum install trace-cmd -y"
        fi
        trace-cmd reset
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "trace-cmd start -p wakeup"
        rlRun "trace-cmd snapshot -s" 16
    rlPhaseEnd
    rlPhaseStartCleanup
        trace-cmd reset
    rlPhaseEnd
rlJournalEnd
