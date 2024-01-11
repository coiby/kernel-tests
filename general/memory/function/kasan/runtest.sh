#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/kasan
#   Description: Check that Kernel-Address-Sanitizer (KASAN) is enabled.
#   Author: David McDougall <dmcdouga@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../../kernel-include/runtest.sh || exit 1

pmgr=$(K_GetPkgMgr)

if [ ${pmgr} == "rpm-ostree" ]; then
    install_opts="-A --idempotent --allow-inactive install -y"
else
    install_opts="install -y"
fi

devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)

# PACKAGE used by test framework, tmt and beaker, and not directly used in script.
# when set
# Package       : kernel
# when not set
# Package       : unknown
# shellcheck disable=SC2034
PACKAGE="kernel"

function RunKasanTest {
    rlPhaseStartSetup
        if ! [[ "$(uname -r)" =~ "debug" ]]; then
            rlLogInfo "Skip Test! KASAN is only enabled for debug kernels."
            rlPhaseEnd
            return
        fi
        if [[ ! "$(uname -r)" =~ "x86_64" ]] && [[ ! "$(uname -r)" =~ "aarch64" ]] && rlIsRHEL "<=8";
        then
            rlLogInfo "Skip Test! KASAN is only enabled for x86_64 and aarch64."
            rlPhaseEnd
            return
        fi
        if ! grep 'CONFIG_KASAN=y' /boot/config-$(uname -r); then
               report_result "SKIP_NOT_SUPPORT" SKIP
               rlPhaseEnd
               return
        fi

        rpm -q ${devel_pkg} || ${pmgr} ${install_opts} ${devel_pkg}
        rpm -q elfutils-libelf-devel || ${pmgr} ${install_opts} elfutils-libelf-devel
        unset ARCH
        rlRun "pushd kasan_test || exit"
        rlRun "make"
    rlPhaseEnd

    rlPhaseStartTest
        dmesg -c
        rlRun "insmod kasan_test.ko"
        rlRun "dmesg -ct > dmesg.log"
        rlFileSubmit dmesg.log
        rlAssertGrep "init kasan test" dmesg.log
        rlAssertGrep "BUG: KASAN: use-after-free in string" dmesg.log
        rlAssertGrep 'Read of size \w+ at addr \w+ by task insmod' dmesg.log -E
        rlAssertGrep "Memory state around the buggy address:" dmesg.log
    rlPhaseEnd

    rlPhaseStartCleanup
        rmmod kasan_test
        make clean
        rm -f dmesg.log
        popd || exit
    rlPhaseEnd
}

rlJournalStart
    RunKasanTest
rlJournalPrintText
rlJournalEnd
