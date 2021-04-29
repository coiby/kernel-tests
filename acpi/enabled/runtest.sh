#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# verify to run on aarch64
if [ "$(uname -i)" != "aarch64" ]; then
    rstrnt-report-result $TEST SKIP
else
    rlJournalStart

        rlPhaseStartTest
            [ -f /var/log/dmesg ] && \
                rlAssertNotGrep "ACPI: Interpreter disabled" /var/log/dmesg

            dmesg > /tmp/dmesg.out
            rlAssertNotGrep "ACPI: Interpreter disabled" /tmp/dmesg.out

            journalctl -b0 > /tmp/journal.out
            rlAssertNotGrep "ACPI: Interpreter disabled" /tmp/journal.out

        rlPhaseEnd

    rlJournalPrintText
    rlJournalEnd
fi
