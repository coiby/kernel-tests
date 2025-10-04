#!/bin/bash
# shellcheck disable=SC2317
eval "$(shellspec - -c) exit 1"

Include accelerators/amd/include/include.sh

Describe "Setting Up AMD ROCm Environment"
  It "Install a repository from a URL"
    When call AmdInstallRepoFromURL "https://example.com/repo.repo"
    The line 1 should include "rlLog Installing repository from https://example.com/repo.repo"
    The line 2 should include "rlRun curl ${_CURL_ARGUMENTS} https://example.com/repo.repo -o /etc/yum.repos.d/repo.repo"
  End
  It "Install the AmdGPU repository"
    Mock AmdInstallRepoFromURL "${AMDGPU_REPO}"
      echo "Installing AMDGPU repository"
    End
    When call AmdAmdGPUInstallRepository
    The output should include "Installing AMDGPU repository"
  End
  It "Install the ROCm repository"
    Mock AmdInstallRepoFromURL "${ROCM_REPO}"
      echo "Installing ROCm repository"
    End
    When call AmdROCmInstallRepository
    The output should include "Installing ROCm repository"
  End

  It "Install EPEL 10 repository"
    OS_VERSION=10.1
    Mock AmdRHELGetVersion
      echo 10.1
    End
    When call AmdEPEL10InstallRepository
    The line 1 should include "rlLog Installing EPEL repository for RHEL ${OS_VERSION}"
    The line 2 should include "rlRun dnf config-manager --add-repo https://dl.fedoraproject.org/pub/epel/${OS_VERSION}/Everything/x86_64"
    The line 3 should include "rlRun rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-10"
  End

  Describe "Specific RHEL versions"
    Mock AmdAmdGPUInstallRepository
      echo "Installing AMDGPU repository"
    End
    Mock AmdROCmInstallRepository
      echo "Installing ROCm repository"
    End
    Mock AmdEPEL10InstallRepository
      echo "Installing EPEL 10 repository"
    End
    It "RHEL9"
      When call AmdROCmSetUpRHEL9
      The line 1 should include "rlLog Installing ROCm on RHEL9"
      The line 2 should include "Installing AMDGPU repository"
      The line 3 should include "Installing ROCm repository"
      The line 4 should include "rlRun dnf install -y ${RHEL9_ROCM_PACKAGES[*]}"
    End
    It "RHEL10"
      When call AmdROCmSetUpRHEL10
      The line 1 should include "rlLog Installing ROCm on RHEL10"
      The line 2 should include "Installing EPEL 10 repository"
      The line 3 should include "rlRun dnf install -y ${RHEL10_ROCM_PACKAGES[*]}"
    End
  End

  Describe "Main function"
    RHEL9_MESSAGE="Installin ROCm on RHEL9"
    RHEL10_MESSAGE="Installin ROCm on RHEL10"
    ERROR_MESSAGE="This script supports only RHEL 9 and RHEL 10"
    Mock AmdROCmSetUpRHEL9
      echo "${RHEL9_MESSAGE}"
    End
    Mock AmdROCmSetUpRHEL10
      echo "${RHEL10_MESSAGE}"
    End

    Parameters
      # rhel_version expected_output support_text
      "10" "${RHEL10_MESSAGE}" "RHEL 10 is supported"
      "9" "${RHEL9_MESSAGE}" "RHEL 9 is supported"
      "8" "${ERROR_MESSAGE}" "Unsupported distro"
    End

    It "${3}"
      Mock rlIsRHEL
        # shellcheck disable=SC2154
        if [[ "$1" == "$rhel_version" ]]; then
          exit 0
        fi
          exit 1
      End
      When call AmdROCmSetUp
      # shellcheck disable=SC2154
      The stdout should include "${expected_output}"
    End
  End
End

Describe "Cleaning up the AMD ROCm environment"

  It "Remove a repository from a URL"
    When call AmdRemoveRepoFromURL "https://example.com/repo.repo"
    The line 1 should include "rlLog Removing repository from https://example.com/repo.repo"
    The line 2 should include "rlRun rm -f /etc/yum.repos.d/repo.repo"
  End
  It "Remove the AmdGPU repository"
    Mock AmdRemoveRepoFromURL "${AMDGPU_REPO}"
      echo "Removing AMDGPU repository"
    End
    When call AmdAmdGPURemoveRepository
    The output should include "Removing AMDGPU repository"
  End
  It "Remove the ROCm repository"
    Mock AmdRemoveRepoFromURL "${ROCM_REPO}"
      echo "Removing ROCm repository"
    End
    When call AmdROCmRemoveRepository
    The output should include "Removing ROCm repository"
  End

  Describe "Specific RHEL versions"
    Mock AmdAmdGPURemoveRepository
      echo "Removing AMDGPU repository"
    End
    Mock AmdROCmRemoveRepository
      echo "Removing ROCm repository"
    End
    Mock AmdEPEL10RemoveRepository
      echo "Removing EPEL 10 repository"
    End

    It "RHEL9"
      When call AmdROCmCleanUpRHEL9
      The line 1 should include "rlLog Removing ROCm on RHEL9"
      The line 2 should include "rlRun dnf remove -y ${RHEL9_ROCM_PACKAGES[*]}"
      The line 3 should include "Removing AMDGPU repository"
      The line 4 should include "Removing ROCm repository"
    End
    It "RHEL10"
      When call AmdROCmCleanUpRHEL10
      The line 1 should include "rlLog Removing ROCm on RHEL10"
      The line 2 should include "rlRun dnf remove -y ${RHEL10_ROCM_PACKAGES[*]}"
      The line 3 should include "Removing EPEL 10 repository"
    End
  End

  Describe "Using the main function to clean up RCOM"
    RHEL_9_MESSAGE="Cleaning up ROCm on RHEL9"
    RHEL_10_MESSAGE="Cleaning up ROCm on RHEL10"
    UNSUPPORTED_MESSAGE="This script supports only RHEL 9 and RHEL 10"
    Mock AmdROCmCleanUpRHEL9
      echo "${RHEL_9_MESSAGE}"
    End
    Mock AmdROCmCleanUpRHEL10
      echo "${RHEL_10_MESSAGE}"
    End

    Parameters
      # rhel_version expected_output support_text
      "10" "${RHEL_10_MESSAGE}" "RHEL 10 is supported"
      "9" " ${RHEL_9_MESSAGE}" "RHEL 9 is supported"
      "8" "$UNSUPPORTED_MESSAGE" "Unsupported distro"
    End

    It "${3}"
      Mock rlIsRHEL
        # shellcheck disable=SC2154
        if [[ "$1" == "$rhel_version" ]]; then
          exit 0
        fi
          exit 1
      End
      When call AmdROCmCleanUp
      # shellcheck disable=SC2154
      The stdout should include "${expected_output}"
    End
  End
End
