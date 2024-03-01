#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../../kernel-include/runtest.sh || exit 1


rlJournalStart
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
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
            # do not panic on fault
            rlRun "sysctl kernel.panic_on_oops=0"
        rlPhaseEnd
        rlPhaseStartTest
            rlRun "pushd ../src"
            rlRun "make all"
            # Read only crash test
            rlRun "nohup echo 1 > /sys/kernel/vkm/null_crash" 139 "(SEGFAULT expected)"
            sleep 1
            rlRun "dmesg > dmesg-crash.log"
            rlAssertGrep "Unable to handle kernel NULL pointer dereference" dmesg-crash.log
            rlFileSubmit dmesg-crash.log
        rlPhaseEnd
        rlPhaseStartCleanup
            rlRun "sysctl kernel.panic_on_oops=1"
            tmt-reboot
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
