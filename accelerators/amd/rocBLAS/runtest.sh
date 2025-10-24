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
. "${CDIR}/../include/include.sh"    || exit 1

rlJournalStart

    rlPhaseStartSetup
        AmdROCmSetUp
        if rlIsRHEL "<10"
        then
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
        fi
        if rlIsRHEL "10"
        then
            LOOKASIDE_URL="https://download.eng.brq.redhat.com/qa/rhts/lookaside/accelerators/amdgpu/rocm/20251013-rocblas"
            ROCBLAS_VERSION="6.4.2-7.el10"
            rlLog "Install rocBLAS and rocBLAS-test"
            # Download both library and test RPMs at matching version
            rlRun "curl -O ${LOOKASIDE_URL}/rocblas-${ROCBLAS_VERSION}.x86_64.rpm"
            rlRun "curl -O ${LOOKASIDE_URL}/rocblas-test-${ROCBLAS_VERSION}.x86_64.rpm"
            # Install the matching library and test RPMs from lookaside, allowing erasure of conflicting EPEL versions
            rlLog "Installing rocBLAS library and test RPMs with matching versions"
            rlRun "dnf install -y --allowerasing ./rocblas-${ROCBLAS_VERSION}.x86_64.rpm ./rocblas-test-${ROCBLAS_VERSION}.x86_64.rpm"
        fi

    rlPhaseEnd

    rlPhaseStartTest
        CMD_PREFIX=""
        TEST_PREFIX=""
        rlLog "Run rocBLAS tests"
        if rlIsRHEL "<10"
        then
            CMD_PREFIX="./"
            rlRun "pushd rocBLAS/build/release/clients/staging"
        else
            TEST_PREFIX="/usr/bin/"
        fi

        rlLog "Run rocBLAS smoke tests"
        rlRun "${CMD_PREFIX}rocblas-test --yaml ${TEST_PREFIX}rocblas_smoke.yaml"
        rlLog "Run rocBLAS bench tests"
        rlRun "${CMD_PREFIX}rocblas-bench -f gemm -r s -m 4000 -n 4000 -k 4000 --lda 4000 --ldb 4000 --ldc 4000 --transposeA N --transposeB T"
        rlRun "${CMD_PREFIX}rocblas-bench -f gemv -r s -m 10240 -n 10240 --lda 10240"
        rlRun "${CMD_PREFIX}rocblas-bench -f axpy -r d -n 102400000"

        if rlIsRHEL "<10"; then
            rlLog "Run rocBLAS examples"
            rlRun "${CMD_PREFIX}rocblas-example-sgemm"
            rlRun "${CMD_PREFIX}rocblas-example-sgemm-strided-batched"
            rlRun "${CMD_PREFIX}rocblas-example-sgemm-multiple-strided-batch"
        else
            rlLog "Skipping rocBLAS examples (not available in RHEL 10 rocblas-test package)"
        fi
        if [[ -n $ROCBLAS_FULL_TEST ]]; then
            # Full rocBLAS test suite is disabled by default
            rlLog "Run full rocBLAS test suite"
            rlRun "${CMD_PREFIX}rocblas-test"
        fi

        if rlIsRHEL "<10"
        then
            rlRun "popd"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        # Remove rocBLAS-specific artifacts
        if rlIsRHEL 10; then
            rlLog "Cleaning up rocBLAS RPMs and test packages"
            rlRun "dnf remove -y rocblas rocblas-test" 0,1
            rlRun "rm -f rocblas-*.rpm"
        fi
        if rlIsRHEL "<10"; then
            if [[ ! -n $ROCBLAS_SKIP_BUILD ]]; then
                rlLog "Cleaning up rocBLAS build directory"
                rlRun "rm -rf rocBLAS"
            fi
        fi
        AmdROCmCleanUp
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
