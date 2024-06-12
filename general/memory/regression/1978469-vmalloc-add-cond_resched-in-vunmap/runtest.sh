#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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
        rlRun "free=$(cat /proc/meminfo | awk '/MemFree/ {print $2}')"
        # shellcheck disable=SC2154
        rlRun "size=$((free/1024/1024-1))"
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "pushd src"
        rlRun "make all"
        rlRun "dmesg -C"
        # kvmalloc-test
        # shellcheck disable=SC2154
        rlRun "insmod kvmalloc-test.ko gb=${size}"
        rlRun "rmmod kvmalloc-test"
        rlRun "dmesg > dmesg-kvmalloc-test.log"
        rlAssertGrep "vmalloc(.*) succeeded" dmesg-kvmalloc-test.log
        rlFileSubmit dmesg-kvmalloc-test.log
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "make clean"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
