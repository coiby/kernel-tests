#!/bin/bash
# Include BeakerLib library
. /usr/share/beakerlib/beakerlib.sh || exit 1

MODULE="unexported_module"
MODFILE="${MODULE}.ko"

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
        pkg_mgr=$(K_GetPkgMgr)
        rlLog "pkg_mgr = ${pkg_mgr}"
        if [[ $pkg_mgr == "rpm-ostree" ]]; then
            export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
        else
            export pkg_mgr_inst_string="-y install"
        fi
        # shellcheck disable=SC2086
        ${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg}
    rlPhaseEnd
    rlPhaseStartTest
    rlRun "make test 2>&1" 2
    rlRun "dmesg > dmesg-test.log"
    rlAssertGrep "Unexported symbol" dmesg-test.log
    rlFileSubmit dmesg-test.log
    rlPhaseEnd

rlPhaseStartCleanup
        rlRun "make clean" 0 "Cleaning up"
        rlRun "rmmod $MODULE" 0-255 "Removing module if it was loaded"
    rlPhaseEnd
rlJournalEnd