#!/bin/bash
# Copyright (c) 2024 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#

# Include environments
. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart

    rlPhaseStartSetup
        if [[ ! -n $KFDTEST_SKIP_BUILD ]]; then
            rlLog "Install build dependencies"
            rlRun "dnf install -y cmake llvm llvm-devel numactl-devel"
            rlLog "Build kfdtest"
            rlRun "dnf install -y cmake llvm llvm-devel"
            rlRun "git clone https://github.com/ROCm/ROCT-Thunk-Interface"
            rlRun "pushd ROCT-Thunk-Interface"
            rlRun "git checkout rocm-6.2.x"
            rlRun "git cherry-pick 8bb5764"
            rlRun "pushd tests/kfdtest/"
            rlRun "mkdir build"
            rlRun "pushd build"
            rlRun "cmake ../ -DCMAKE_PREFIX_PATH='/opt/rocm-6.2.0'"
            rlRun "make -j$(nproc)"
            rlLog "Copy excludes file"
            rlRun "cp ../../../../kfdtest.exclude ."
            rlRun "popd"
            rlRun "popd"
            rlRun "popd"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Run kfdtest tests"
        # TODO: Select correct filter for different systems as they get available
        rlRun "pushd ROCT-Thunk-Interface/tests/kfdtest/build"
        rlRun "./run_kfdtest.sh -p RHEL9"
        rlRun "popd"
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
