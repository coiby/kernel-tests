#!/bin/bash
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

# Curl arguments
_CURL_ARGUMENTS="-sL --retry 5 --retry-delay 10 --retry-max-time 60"

# Default repository URLs
AMDGPU_REPO="https://raw.githubusercontent.com/containers/ai-lab-recipes/refs/heads/main/training/amd-bootc/repos.d/amdgpu.repo"
ROCM_REPO="https://raw.githubusercontent.com/containers/ai-lab-recipes/refs/heads/main/training/amd-bootc/repos.d/rocm.repo"

# Rocm packages to be installed
RHEL10_ROCM_PACKAGES=(rocm rocm-devel)
RHEL9_ROCM_PACKAGES=(rocm)

function AmdInstallRepoFromURL() {
  local repo_url="${1}"
  local repo_file_name=$(basename "${repo_url}")
  rlLog "Installing repository from ${repo_url}"
  rlRun "curl ${_CURL_ARGUMENTS} ${repo_url} -o /etc/yum.repos.d/${repo_file_name}"
}

function AmdRHELGetVersion() {
  grep ^VERSION_ID= /etc/os-release | cut -d = -f 2 | cut -d \" -f 2
}

function AmdAmdGPUInstallRepository() {
  AmdInstallRepoFromURL "${AMDGPU_REPO}"
}

function AmdROCmInstallRepository() {
  AmdInstallRepoFromURL "${ROCM_REPO}"
}

function AmdEPEL10InstallRepository() {
  local os_version=$(AmdRHELGetVersion)
  local repo_url="https://dl.fedoraproject.org/pub/epel/${os_version}/Everything/x86_64"
  rlLog "Installing EPEL repository for RHEL ${os_version}"
  rlRun "dnf config-manager --add-repo ${repo_url}"
  rlRun "rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-10"
}

function AmdROCmSetUpRHEL9() {
  rlLog "Installing ROCm on RHEL9"
  AmdAmdGPUInstallRepository
  AmdROCmInstallRepository
  rlRun "dnf install -y ${RHEL9_ROCM_PACKAGES[*]}"
}

function AmdROCmSetUpRHEL10() {
  rlLog "Installing ROCm on RHEL10"
  AmdEPEL10InstallRepository
  rlRun "dnf install -y ${RHEL10_ROCM_PACKAGES[*]}"
}

function AmdROCmSetUp() {
  if rlIsRHEL 9; then
    AmdROCmSetUpRHEL9
  elif rlIsRHEL 10; then
    AmdROCmSetUpRHEL10
  else
    rlFail "This script supports only RHEL 9 and RHEL 10"
  fi
}

# Clean Up functions
function AmdRemoveRepoFromURL() {
  local repo_url="${1}"
  local repo_file_name=$(basename "${repo_url}")
  rlLog "Removing repository from $repo_url"
  rlRun "rm -f /etc/yum.repos.d/${repo_file_name}"
}

function AmdAmdGPURemoveRepository() {
  AmdRemoveRepoFromURL "${AMDGPU_REPO}"
}

function AmdROCmRemoveRepository() {
  AmdRemoveRepoFromURL "${ROCM_REPO}"
}

function AmdEPEL10RemoveRepository() {
  local os_version=$(AmdRHELGetVersion)
  local repo_url="https://dl.fedoraproject.org/pub/epel/${os_version}/Everything/x86_64"
  local temp_url=${repo_url/"https://"/}
  local repo_file_name=${temp_url//\//_}.repo
  rlLog "Removing EPEL repository for RHEL ${os_version}"
  rlRun "rm -f /etc/yum.repos.d/${repo_file_name}"
}

function AmdROCmCleanUpRHEL10() {
  rlLog "Removing ROCm on RHEL10"
  rlRun "dnf remove -y ${RHEL10_ROCM_PACKAGES[*]}"
  AmdEPEL10RemoveRepository
}

function AmdROCmCleanUpRHEL9() {
  rlLog "Removing ROCm on RHEL9"
  rlRun "dnf remove -y ${RHEL9_ROCM_PACKAGES[*]}"
  AmdAmdGPURemoveRepository
  AmdROCmRemoveRepository
}

function AmdROCmCleanUp() {
  if rlIsRHEL 9; then
    AmdROCmCleanUpRHEL9
  elif rlIsRHEL 10; then
    AmdROCmCleanUpRHEL10
  else
    rlFail "This script supports only RHEL 9 and RHEL 10"
  fi
}
