#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
# Skip if running on unsupported hardware
    rlPhaseStartTest
        rlRun -l "dmidecode --type 42 > /tmp/dmidecode.log"
            if grep -i redfish /tmp/dmidecode.log ; then
                rlPass "Moving on, host is redfish compatible"
            else
                rlLog "Hardware doesn't support redfish, skipping test"
                rhts-report-result "$TEST" SKIP "$OUTPUTFILE"
                exit
            fi
    rlPhaseEnd

# Check that redfish-finder rpm is installed
    rlPhaseStartTest
        if ! rlCheckRpm redfish-finder; then
            dnf -y install redfish-finder
            rlAssertRpm redfish-finder
        fi
    rlPhaseEnd

# Verify redfish-finder-service starts successfully
    rlPhaseStartTest
        rlServiceStart redfish-finder
    rlPhaseEnd

# Verify redfish-finder log entries
    rlPhaseStartTest
        journalctl -b0 > /tmp/journal.out
        rlAssertGrep "BMC is now reachable via hostname redfish-localhost" /tmp/journal.out
        rlAssertGrep "Started Redfish host api discovery service" /tmp/journal.out
    rlPhaseEnd

# Verify redfish entry was added to /etc/hosts
    rlPhaseStartTest
        rlAssertGrep "redfish-localhost" /etc/hosts
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
