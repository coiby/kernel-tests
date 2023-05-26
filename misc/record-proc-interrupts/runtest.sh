#!/bin/bash

# Enable TMT testing for RHIVOS
auto_include=../../automotive/include/include.sh
[ -f $auto_include ] && . $auto_include
declare -F kernel_automotive && kernel_automotive

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest
        LOGFILE=proc_interrupts.out
        rlRun "cat /proc/interrupts > ${LOGFILE}"
        rlFileSubmit ${LOGFILE}
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
