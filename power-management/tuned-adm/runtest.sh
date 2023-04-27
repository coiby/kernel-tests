#!/bin/bash

. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

rlPhaseStartSetup
rlRun "yum install -y tuned"
rlAssertRpm "tuned"
rlShowPackageVersion "tuned"
rlRun "systemctl enable --now tuned.service"
rlRun "tuned-adm profile_info" # current profile
rlRun "tuned-adm active"
rlRun "tuned-adm list"
INITIAL_PROFILE=$(tuned-adm active | awk '{print $4}')
PROFILES_LIST=$(tuned-adm list | grep '^-' | awk '{print $2}')
rlPhaseEnd

for profile in $PROFILES_LIST
do
        rlPhaseStart FAIL $profile
        rlRun "tuned-adm profile_info $profile"
        rlRun "tuned-adm profile $profile"
        rlPhaseEnd
done

rlPhaseStartCleanup
rlRun "tuned-adm profile $INITIAL_PROFILE"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
