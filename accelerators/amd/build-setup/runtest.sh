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


ROCM_REPO_URL="https://raw.githubusercontent.com/containers/ai-lab-recipes/refs/heads/main/training/amd-bootc/repos.d/rocm.repo"
AMDGPU_REPO_URL="https://raw.githubusercontent.com/containers/ai-lab-recipes/refs/heads/main/training/amd-bootc/repos.d/amdgpu.repo"

EPEL10_REPO_URL="https://dl.fedoraproject.org/pub/epel/10/Everything/x86_64/"


rlJournalStart

    rlPhaseStartTest
        rlLog "Install ROCm and AMDGPU needed bits"
        if rlIsRHEL "<10"
        then
            rlLog "Install wget"
            rlRun "dnf install -y wget"
            rlLog "RHEL9: Use AMD ROCm repositories"
            rlRun "wget ${ROCM_REPO_URL} -P /etc/yum.repos.d/"
            rlRun "wget  ${AMDGPU_REPO_URL} -P /etc/yum.repos.d/"
            rlRun "echo 'exclude=amdgpu-dkms-* dkms-*' >> /etc/dnf/dnf.conf"
            rlRun "dnf install -y libdrm-* rocm6.2.0"
        else
            rlLog "RHEL10: Use EPEL10 repositories"
            rlRun "dnf config-manager --add-repo ${EPEL10_REPO_URL}"
            rlRun "dnf install --nogpgcheck -y libdrm-* rocm"
        fi
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
