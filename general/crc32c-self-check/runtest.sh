#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

    rlPhaseStartSetup
        pushd crc32c-self-check
        if [ -f crc32c-self-check.ko ]; then
            rlRun "make clean" 0 "Cleaning old crc32c-self-check builds"
        fi
        rlRun "make" 0 "Building crc32c-self-check kernel module"
        popd
        rlRun "modprobe libcrc32c" 0 "Loading libcrc32c module"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "dmesg --clear" 0 "Clearing dmesg logs"
        for i in {01..100} ; do
            rlRun "insmod ./crc32c-self-check/crc32c-self-check.ko" 0 \
                  "Running crc32c self-test $i of 100"
            rlRun "rmmod crc32c-self-check" 0 "Test finished"
            rlRun "dmesg --read-clear > dmesg.$i" 0 \
                  "Reading and clearing dmesg logs"
            if grep -q 'i:.*oldcrc:.*crc:.*' dmesg.$i ; then
                rlFail "Bad CRC calculation"
            fi
        done
    rlPhaseEnd

    rlPhaseStartCleanup
        cat dmesg.* > dmesg
        rlFileSubmit dmesg
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
