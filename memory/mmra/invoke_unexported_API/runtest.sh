#!/bin/bash
# Include BeakerLib library
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1
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
        ${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg}
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "make test 2> test.log" 2
        rlAssertGrep "ERROR: modpost: \"unexported_kernel_symbol\"" test.log
        rlRun "insmod unexported_module.ko 2> test.log" 0-255
        # rlRun "dmesg > dmesg-test.log"
        rlAssertGrep "ERROR: could not load module unexported_module.ko: No such file or directory" test.log
        #rlFileSubmit dmesg-test.log
        rlFileSubmit test.log
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make clean" 0
        rlRun "rmmod $MODULE" 0-255
    rlPhaseEnd
rlJournalEnd