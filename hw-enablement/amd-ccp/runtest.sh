#!/bin/bash

# include beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

RNG_LOOPS=${RNG_LOOPS:-10}
CRYPTO_LOOP=${CRYPTO_LOOP:-10}

ccp_drivers="\
hmac-sha256-ccp sha256-ccp hmac-sha224-ccp sha224-ccp hmac-sha1-ccp sha1-ccp cmac-aes-ccp \
xts-aes-ccp rfc3686-ctr-aes-ccp ctr-aes-ccp ofb-aes-ccp cfb-aes-ccp cbc-aes-ccp ecb-aes-ccp"

rlJournalStart

rlPhaseStartSetup
    rlRun "tmpdir=\$(mktemp -d)"
    rlRun "pushd $tmpdir"

rlPhaseEnd

rlPhaseStartTest

    # Unload ccp_crypto if its is loaded
    # This step is needed because ccp_crypto uses ccp
    rlRun "rmmod ccp_crypto" 0,1
    rlRun "lsmod | grep -w ccp_crypto > /dev/null" 1

    for i in $(seq $RNG_LOOPS); do
        rlLog "RNG LOOP # $i"

        # Save the timestamp (needed for journalctl)
        since="$(date -u '+%Y-%m-%d %H:%M:%S')"

        # Start rngd service
        rlRun "systemctl start rngd.service"

        # Check if ccp driver is loaded
        rlRun "lsmod | grep -w ccp > /dev/null"

        # Verify that the speed of /dev/hwrng is at least 1 MiB/s
        rlRun "timeout 1 dd if=/dev/hwrng of=/dev/null bs=1024 count=1024 iflag=fullblock"

        # Check the randomness of /dev/hwrng
        rlRun "cat /dev/hwrng | timeout 24 rngtest -c 10000 2>&1 | tee rngtest.log" 0,1
        rlRun "rng_fails=\"\$(sed -n 's/^rngtest: FIPS 140-2 failures:\s*//p' rngtest.log)\""
        rlRun "[ ${rng_fails:-X} -le 100 ]"

        # Verify that the speed of /dev/random is at least 100 kiB/s
        rlRun "timeout 1 dd if=/dev/random of=/dev/null bs=1024 count=100 iflag=fullblock"

        # Check the randomness of /dev/random
        rlRun "cat /dev/random | timeout 240 rngtest -c 10000 2>&1 | tee rngtest.log" 0,1
        rlRun "rng_fails=\"\$(sed -n 's/^rngtest: FIPS 140-2 failures:\s*//p' rngtest.log)\""
        rlRun "[ ${rng_fails:-X} -le 100 ]"

        # Verify that entropy pool is at least 2048
        rlRun "entropy_avail=\"\$(cat /proc/sys/kernel/random/entropy_avail)\""
        rlRun "[ $entropy_avail -ge 2048 ]"

        # Stop the rngd service
        rlRun "systemctl stop rngd.service"

        # Unload ccp module
        rlRun "rmmod ccp"
        rlRun "lsmod | grep -w ccp > /dev/null" 1

        # Verify that the /dev/random speed drops below 10 kiB/s
        rlRun "timeout 1 dd if=/dev/random of=/dev/null bs=1024 count=10 iflag=fullblock" 124

        # Verify that entropy pool falled below 2048
        rlRun "entropy_avail=\"\$(cat /proc/sys/kernel/random/entropy_avail)\""
        rlRun "[ $entropy_avail -lt 2048 ]"

        # Check journalctl for error messages
        rlRun "journalctl --utc --since=\"$since\" --unit=rngd --no-pager | tee rngd.log"
        rlRun "grep 'error' rngd.log" 1

        # Load ccp module
        rlRun "modprobe ccp"

    done

    for i in $(seq $CRYPTO_LOOP); do
        rlLog "CRYPTO LOOP # $i"

        # Reload ccp_crypto module
        if [ $i -gt 1 ]; then
            rlRun "rmmod ccp_crypto"
            rlRun "lsmod | grep -w ccp_crypto > /dev/null" 1
        fi
        rlRun "modprobe ccp_crypto"

        # Check if ccp_crypto driver is loaded
        rlRun "lsmod | grep -w ccp_crypto > /dev/null"

        # Check if crypto drivers are advertised in /proc/crypto
        for driver in $ccp_drivers; do
            rlRun "grep -w $driver /proc/crypto > /dev/null"
        done

    done

rlPhaseEnd

rlPhaseStartCleanup
    rlRun "popd"
    rlRun "rm -rf $tmpdir"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd

