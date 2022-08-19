#!/bin/bash
# Include rhts environment
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
        rlRun "trace-cmd record -p wakeup sleep 2"
        rlRun "trace-cmd split -e 1 > 1328692-split-log 2>&1" 255
        cat 1328692-split-log
        rlRun "grep 'trace-cmd split does not work with latency traces' 1328692-split-log"
    rlPhaseEnd
    rlPhaseStartCleanup
        trace-cmd reset
    rlPhaseEnd
rlJournalEnd
