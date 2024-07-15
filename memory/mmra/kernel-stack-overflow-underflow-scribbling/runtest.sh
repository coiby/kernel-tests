#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../automotive/include/rhivos.sh || exit 1

run_insert_mode() {
    mode=$1
    expected_restart_count=$2
    rlPhaseStartTest
        if [ $TMT_TEST_RESTART_COUNT -ne $expected_restart_count ]; then
            echo "Skipping overflow test on this restart"
        else
            rlRun "rm /var/tmp/stackman/remove_after_module_insert"
            rlRun "insmod stackman.ko testmode=$mode" 0 "Insmod stackman.ko $mode"
            rlRun "sleep 20"
        fi
    rlPhaseEnd
}

check_disconnection() {
    if [ -f /var/tmp/stackman/remove_after_module_insert ]; then
        rlFail "Disconnection was not caused by reboot. Bailing out"
        exit 1
    else
        echo "Disconnection caused by reboot"
    fi
}

echo "TMT_TEST_RESTART_COUNT $TMT_TEST_RESTART_COUNT"
rlJournalStart
    rlPhaseStartSetup
        # Instalation of kernel-automotive-devel from the .fmf is not persistent
        # reinstall here
        kernel_automotive
        if [ $? -eq 0 ]; then
            rlRun "install_kernel_automotive_devel"
        fi
        rlRun "if [ -d /var/tmp/stackman ]; then rm -fR /var/tmp/stackman; fi"
        rlRun "mkdir /var/tmp/stackman"
        # Create a flag file to make sure reboot came from the module and it was
        # not a random network disconnection
        rlRun "touch /var/tmp/stackman/remove_after_module_insert"
        rlRun "cp stackman.c stacklib.c Makefile /var/tmp/stackman"
        rlRun "pushd /var/tmp/stackman"
        rlRun "set -o pipefail"
        rlRun "make"
        rlRun "sysctl kernel.panic_on_oops=1" 0 "Set panic on OOPS"
        rlRun "sysctl kernel.panic=5" 0 "Set kernel to reboot after 5 seconds on panic"
    rlPhaseEnd

    run_insert_mode overflow 0
    run_insert_mode underflow 1
    run_insert_mode scribbling 2

    rlPhaseStartCleanup
        rlRun "rm -rf /var/tmp/stackman" 0 "Remove tmp directory"
    rlPhaseEnd
rlJournalEnd
