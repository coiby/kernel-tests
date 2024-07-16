#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1

run_insert_mode() {
    mode=$1
    expected_restart_count=$2
    rlPhaseStartTest
        if [ $TMT_TEST_RESTART_COUNT -ne $expected_restart_count ]; then
            rlLog "Skipping ${mode} test on this restart"
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
        rlLog "Disconnection caused by reboot"
    fi
}

echo "TMT_TEST_RESTART_COUNT $TMT_TEST_RESTART_COUNT"
rlJournalStart
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

    run_insert_mode overflow 0
    run_insert_mode underflow 1
    run_insert_mode scribbling 2

    rlPhaseStartCleanup
        rlRun "sysctl kernel.panic=0" 0 "Set kernel back to default, do not reboot on panic"
        rlRun "rm -rf /var/tmp/stackman" 0 "Remove tmp directory"
    rlPhaseEnd
rlJournalEnd
