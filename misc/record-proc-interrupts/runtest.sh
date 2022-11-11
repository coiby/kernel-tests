#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest
        LOGFILE=proc_interrupts.out
        rlRun "cat /proc/interrupts > ${LOGFILE}"
        rlFileSubmit ${LOGFILE}
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
