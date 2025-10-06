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

# Include the AMD accelerators library
CDIR=$(dirname "${FILE}")
. "${CDIR}/../include.sh"    || exit 1


rlJournalStart
  rlPhaseStartSetup
    AmdROCmSetUp
    rlRun "git clone --branch rocm-6.4.1 https://github.com/ROCm/ROCR-Runtime.git $HOME/src/ROCR-Runtime"
    rlRun "cmake -S $HOME/src/ROCR-Runtime/rocrtst/suites/test_common -B $HOME/src/ROCR-Runtime/build-rocrtst -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/opt/rocm"
    rlRun "cmake --build $HOME/src/ROCR-Runtime/build-rocrtst -j"
    rlRun "export LD_LIBRARY_PATH=$HOME/src/ROCR-Runtime/rocrtst/thirdparty/lib:/opt/rocm/lib:$LD_LIBRARY_PATH"
  rlPhaseEnd

  rlPhaseStartTest
    rlRun "$HOME/src/ROCR-Runtime/build-rocrtst/rocrtst64 --gtest_filter=-rocrtstFunc.Max_Reference_Count --gtest_output=xml:/var/tmp/rocrtst_full.xml"
  rlPhaseEnd

  rlPhaseStartCleanup
    rlRun "dnf remove -y cmake gcc-c++ git libtool-ltdl make numactl-devel"
    rlRun "rm -rf $HOME/src/ROCR-Runtime"
    AmdROCmCleanUp
  rlPhaseEnd

rlJournalEnd

rlJournalPrintText

