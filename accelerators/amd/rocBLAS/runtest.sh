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
        if [[ ! -n $ROCBLAS_SKIP_BUILD ]]; then
            rlLog "Install EPEL repositories"
            rlRun "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
            rlLog "Install build dependencies"
            rlRun "dnf install -y cmake gfortran gtest-devel"
            rlLog "Build rocBLAS tests"
            rlRun "git clone --branch=release/rocm-rel-6.2 --depth=1 https://github.com/ROCm/rocBLAS.git"
            rlRun "pushd rocBLAS/"
            rlRun "./install.sh --clients-only"
            rlRun "popd"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Run rocBLAS tests"
        rlRun "pushd rocBLAS/build/release/clients/staging"
        rlLog "Run rocBLAS smoke tests"
        rlRun "./rocblas-test --yaml rocblas_smoke.yaml"
        rlLog "Run rocBLAS bench tests"
        rlRun "./rocblas-bench -f gemm -r s -m 4000 -n 4000 -k 4000 --lda 4000 --ldb 4000 --ldc 4000 --transposeA N --transposeB T"
        rlRun "./rocblas-bench -f gemv -r s -m 10240 -n 10240 --lda 10240"
        rlRun "./rocblas-bench -f axpy -r d -n 102400000"
        rlLog "Run rocBLAS examples"
        rlRun "./rocblas-example-sgemm"
        rlRun "./rocblas-example-sgemm-strided-batched"
        rlRun "./rocblas-example-sgemm-multiple-strided-batch"
        if [[ -n $ROCBLAS_FULL_TEST ]]; then
            # Full rocBLAS test suite is disabled by default
            rlLog "Run full rocBLAS test suite"
            rlRun "./rocblas-test"
        fi
        rlRun "popd"
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
