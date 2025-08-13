#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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
. ../../kernel-include/runtest.sh || exit 1
. ../../cmdline_helper/libcmd.sh || exit 1


rlJournalStart
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
        rlPhaseStartSetup
            rlShowRunningKernel
            devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
            selftests_pkg=$(K_GetRunningKernelRpmSubPackageNVR selftests-internal)
            pkg_mgr=$(K_GetPkgMgr)
            rlLog "pkg_mgr = ${pkg_mgr}"
            if [[ $pkg_mgr == "rpm-ostree" ]]; then
                export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
            else
                export pkg_mgr_inst_string="-y install"
            fi
            # shellcheck disable=SC2086
            ${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg} ${selftests_pkg}
            rlRun "change_cmdline 'secretmem.enable=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
    if [ "${REBOOTCOUNT}" -eq 1 ]; then
        rlPhaseStartTest memfd_secret
            rlRun "/usr/libexec/kselftests/mm/memfd_secret"
        rlPhaseEnd
        rlPhaseStartCleanup
            rlRun "change_cmdline '-secretmem.enable=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
