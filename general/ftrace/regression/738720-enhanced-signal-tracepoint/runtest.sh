#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "Initialize 'Teardown'"
        rlRun "SetEvent 'signal:signal_generate'" || rlDie
        rlRun "echo 1 > ${T_PATH_TRACE_ON}"       || rhDie
        rlRun "echo > ${T_PATH_TRACE_TRACE}"      || rlDie
    rlPhaseEnd

    rlPhaseStartTest
        rlWatchdog 'sleep 60 & :' 1
        rlAssertGrep 'grp=[0-9]+ res=[0-9]+' ${T_PATH_TRACE_TRACE} -E
        rstrnt-report-log -l ${T_PATH_TRACE_TRACE}
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "Teardown"
    rlPhaseEnd
rlJournalEnd
