#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# source fwts include/library
. ../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        fwtsSetup
    rlPhaseEnd

    if [ "$(uname -i)" = "aarch64" ]; then
        # the aarch64 kernel has CONFIG_STRICT_DEVMEM=y so tools like acpidump
        # and fwts cannot read the ACPI tables directly from /dev/mem,
        # but they are availble in /sys/firmware/acpi/tables/*
        # ... however ...
        # fwts -t /path/to/tables expects the files to have a .dat extension
        # so it cannot use /sys/firmware/acpi/tables/* directly (argh)
        rlPhaseStart FAIL "Extract ACPI tables"
            rlRun "ACPITABLES=$(mktemp -d -p /mnt/testarea acpitables.XXXXXX)" 0 "Creating ACPI tables directory"
            for T in /sys/firmware/acpi/tables/* ; do
                table="$(basename $T).dat"
                [ -f $T ] && rlRun "cp $T $ACPITABLES/${table}" 0 "Dumping ACPI table $table"
            done
            ACPITABLESARG="-t $ACPITABLES"
        rlPhaseEnd
    fi

    rlPhaseStartTest
        rlLog "Running the following fwts tests: $(fwts --batch --show-tests)"
        rlRun "fwts --batch $ACPITABLESARG" 0,1 "run fwts in batch mode"
    rlPhaseEnd

    fwtsReportResults

    rlPhaseStartCleanup
        fwtsCleanup
        if [ "$(uname -i)" = "aarch64" ]; then
            rlRun "rm -fr $ACPITABLES" 0 "Removing ACPI tables tmp directory"
        fi
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
