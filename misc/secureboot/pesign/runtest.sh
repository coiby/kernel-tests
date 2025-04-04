#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

rlPhaseStartSetup
if ! rlCheckRpm "pesign"; then
    yum install "pesign" -y
    rlAssertRpm "pesign"
fi
rlShowPackageVersion "pesign"
rlPhaseEnd

rlPhaseStartTest kernel
rlShowPackageVersion "kernel"
set -o pipefail
rlRun -s "pesign -i /boot/vmlinuz-$(uname -r) -S | tee pesign-log"
set +o pipefail
grep 'common name' pesign-log > pesign-signer
rlAssertGrep "Red Hat\|Fedora\|CentOS" pesign-signer
rlAssertNotGrep "Red Hat Test Certificate" pesign-signer # known point of failure
rlAssertNotGrep "No signatures found" pesign-log

rlPhaseEnd

# this package is not from kernel, I'm not sure if we should do the check here, but for now...
if [[ "$(arch)" == x86_64 ]]; then
    rpm -q shim-x64 > /dev/null 2>&1 || yum install "shim-x64" -y

    # skip if shim-x64 couldn't be installed
    if rpm -q shim-x64 > /dev/null 2>&1; then
        rlPhaseStartTest shim-x64
        rlShowPackageVersion "shim-x64"
        set -o pipefail
        rlRun -s "pesign -i /boot/efi/EFI/BOOT/BOOTX64.EFI -S | tee pesign-log"
        set +o pipefail
        grep 'common name' pesign-log > pesign-signer
        rlAssertGrep "Microsoft" pesign-signer
        rlAssertNotGrep "Red Hat\|Fedora\|CentOS" pesign-signer
        rlAssertNotGrep "No signatures found" pesign-log
        rlPhaseEnd
    fi
fi

rm pesign-log pesign-signer

rlJournalPrintText
rlJournalEnd
