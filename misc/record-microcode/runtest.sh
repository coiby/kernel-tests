#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest
        LOGFILE=cpu_microcode_version.out
        rlRun "grep . /sys/devices/system/cpu/cpu*/microcode/version > ${LOGFILE}"
        rlFileSubmit ${LOGFILE}
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
