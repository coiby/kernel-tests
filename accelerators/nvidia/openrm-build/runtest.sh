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

# shellcheck disable=SC2034

# Include environments
. /usr/share/beakerlib/beakerlib.sh || exit 1


# Test configuration
# TODO: Make it customizable so we can test different driver versions
# RHEL AI versions info: https://gitlab.com/redhat/rhel-ai/containers/nvidia-bootc/-/blob/main/argfile.conf?ref_type=heads
DRIVER_VERSION="570.124.06"
CUDA_VERSION='12.8.1'
BASE_URL='https://us.download.nvidia.com/tesla'
SPECFILE_REPO='https://github.com/NVIDIA/yum-packaging-precompiled-kmod'

DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1)
CUDA_VERSION_ARRAY=(${CUDA_VERSION//./ })
CUDA_DASHED_VERSION=${CUDA_VERSION_ARRAY[0]}-${CUDA_VERSION_ARRAY[1]}


# Environment information
KCORE_PACKAGE="kernel-core-$(uname -r)"
KVER=$(rpm -q --qf "%{VERSION}" ${KCORE_PACKAGE})
KREL=$(rpm -q --qf "%{RELEASE}" ${KCORE_PACKAGE} | sed 's/\.el\(8\|9\|10\)\(_.\)*$//')
KDIST=$(rpm -q --qf "%{RELEASE}" ${KCORE_PACKAGE} | awk -F '.' '{ print "."$NF}')
OS_VERSION=$(grep "^VERSION=" /etc/os-release)
OS_VERSION_MAJOR=$(grep "^VERSION=" /etc/os-release | cut -d '=' -f 2 | sed 's/"//g' | cut -d '.' -f 1)
BUILD_ARCH=$(arch)
TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//')

if [ ${OS_VERSION_MAJOR} == 10 ]; then
    OS_VERSION_MAJOR=9
    echo "WARNING: Changing OS_VERSION_MAJOR to 9 for compatibility"
fi


rlJournalStart
    rlPhaseStartSetup
        rlLog "Variables information"
        rlLog "Kernel core package: ${KCORE_PACKAGE}"
        rlLog "Kernel version: ${KVER}"
        rlLog "Kernel release: ${KREL}"
        rlLog "Kernel dist: ${KDIST}"
        rlLog "OS Version: ${OS_VERSION}"
        rlLog "OS Version major: ${OS_VERSION_MAJOR}"
        rlLog "Build arch: ${BUILD_ARCH}"
        rlLog "Target arch: ${TARGET_ARCH}"

        rlLog "Setting up OpenRM build"
        # Install kernel-devel package for current kernel if not present
        dnf install -y kernel-devel-${KVER}-${KREL}${KDIST}
        # Install openssl as it is not installed by default
        dnf install -y openssl
        git clone --depth 1 --single-branch -b rhel${OS_VERSION_MAJOR} ${SPECFILE_REPO}

        cd yum-packaging-precompiled-kmod
        mkdir BUILD BUILDROOT RPMS SRPMS SOURCES SPECS
        mkdir nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}
        curl -sLOf ${BASE_URL}/${DRIVER_VERSION}/NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run
        sh ./NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run --extract-only --target tmp
        mv tmp/kernel-open nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}/kernel
        tar -cJf SOURCES/nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}.tar.xz nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}
        echo "Moving specfile to SPECS"
        mv kmod-nvidia.spec SPECS/
        # Generate certificate needed to build the RPM package
        openssl req -x509 -new -nodes -utf8 -sha256 -days 36500 -batch \
            -config ../x509-configuration.ini \
            -outform DER -out SOURCES/public_key.der \
            -keyout SOURCES/private_key.priv
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Building OpenRM driver"
        rlRun 'rpmbuild \
            --define "% _arch ${BUILD_ARCH}" \
            --define "%_topdir $(pwd)" \
            --define "debug_package %{nil}" \
            --define "kernel ${KVER}" \
            --define "kernel_release ${KREL}" \
            --define "kernel_dist ${KDIST}" \
            --define "driver ${DRIVER_VERSION}" \
            --define "driver_branch ${DRIVER_STREAM}" \
            --define "vendor ${VENDOR:-undefined}" \
            --define "_buildhost ${RPM_HOST:-${HOSTNAME}}" \
            -v -bb SPECS/kmod-nvidia.spec'
        rlLog "Installing OpenRM driver"
        rlRun "rpm -ivh RPMS/x86_64/kmod-nvidia-${DRIVER_VERSION}-${KVER}-${KREL}-${DRIVER_VERSION}-3${KDIST}.${BUILD_ARCH}.rpm"

        rlLog "Installing CUDA"
        rlRun "dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel${OS_VERSION_MAJOR}/${TARGET_ARCH}/cuda-rhel${OS_VERSION_MAJOR}.repo"
        rlRun "dnf -y module enable nvidia-driver:${DRIVER_STREAM}-open/default"
        rlRun "dnf install -y --nogpgcheck \
            nvidia-driver-${DRIVER_VERSION} \
            nvidia-driver-cuda-${DRIVER_VERSION} \
            nvidia-driver-libs-${DRIVER_VERSION} \
            cuda-compat-${CUDA_DASHED_VERSION} \
            cuda-cudart-${CUDA_DASHED_VERSION} \
            nvidia-persistenced-${DRIVER_VERSION} \
            nvidia-container-toolkit"

    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
