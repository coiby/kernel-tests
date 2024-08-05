#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1

# Assign global env var to avoid shellcheck warning
testmode=${testmode:-""}

run_insert_mode() {
    mode=$1
    rlPhaseStartTest
        rlRun "rm -f /var/tmp/stackman/remove_after_module_insert"
        rlRun "sync;sync;sync"  # make sure fs is synced before the crash
        rlRun "insmod stackman.ko testmode=$mode" 0 "Insmod stackman.ko $mode"
        rlRun "sleep 20"
        # If we reach this point the machine did not reboot; the test failed
        rlFail "System did not reboot (test fail)"
    rlPhaseEnd
}

check_disconnection() {
    rlPhaseStartTest
        if [ -f /var/tmp/stackman/remove_after_module_insert ]; then
            rlFail "Disconnection was not caused by kernel module. Bailing out"
            exit 1
        else
            rlLog "Disconnection caused by kernel module as expected"
        fi
    rlPhaseEnd
}

echo "TMT_TEST_RESTART_COUNT $TMT_TEST_RESTART_COUNT"
rlJournalStart
    if [ $TMT_TEST_RESTART_COUNT == 0 ]; then
        rlPhaseStartSetup
            devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
            pkg_mgr=$(K_GetPkgMgr)
            rlLog "pkg_mgr = ${pkg_mgr}"
            if [[ $pkg_mgr == "rpm-ostree" ]]; then
                export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
            else
                export pkg_mgr_inst_string="-y install"
            fi
            # Install kernel automotive devel
            # shellcheck disable=SC2086
            ${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg}

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

        run_insert_mode $testmode
    else
        check_disconnection

        rlPhaseStartCleanup
            rlRun "sysctl kernel.panic=0" 0 "Set kernel back to default, do not reboot on panic"
            rlRun "rm -rf /var/tmp/stackman" 0 "Remove tmp directory"
        rlPhaseEnd
    fi
rlJournalEnd
