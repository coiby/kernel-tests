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
        rlLog "Building CUDA samples"
        rlRun "git clone https://github.com/NVIDIA/cuda-samples.git"
        rlRun "pushd cuda-samples"
        rlRun "mkdir build"
        rlRun "pushd build"
        rlRun "cmake .."
        rlRun "make deviceQuery"
        rlRun "make cudaTensorCoreGemm"
        rlRun "make simpleCUBLAS"
        rlRun "make batchCUBLAS"
        rlRun "popd"
        rlRun "popd"
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Executing deviceQuery"
        rlRun "./cuda-samples/build/Samples/1_Utilities/deviceQuery/deviceQuery"

        rlLog "Executing cudaTensorCoreGemm"
        rlRun "./cuda-samples/build/Samples/3_CUDA_Features/cudaTensorCoreGemm/cudaTensorCoreGemm"

        rlLog "Executing simpleCUBLAS"
        rlRun "./cuda-samples/build/Samples/4_CUDA_Libraries/simpleCUBLAS/simpleCUBLAS"

        rlLog "Executing batchCUBLAS"
        rlRun "./cuda-samples/build/Samples/4_CUDA_Libraries/batchCUBLAS/batchCUBLAS"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlLog "Cleaning up"
        rlRun "rm -rf cuda-samples"
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText

