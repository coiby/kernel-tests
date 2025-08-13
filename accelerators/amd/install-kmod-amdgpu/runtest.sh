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

if [ -z "${BREW_TASK_ID}" ]; then
    echo "ERROR: BREW_TASK_ID environment variable must be set." >&2
    exit 1
fi

rlJournalStart

    rlPhaseStartSetup
        # Run provisioning only on the initial invocation
        if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq "0" ]; then
          # ---------------------------------------------------------------------------
          # 1. Enable RCM tools repo so we can use brewkoji.
          # 2. Download all artifacts from the specified Brew task ID.
          # 3. Pick the kmod-amdgpu RPM, extract the kernel-release it targets.
          # 4. Ensure matching kernel RPMs are present (download from Brew build if needed).
          # 5. Install kernel + kmod, set default kernel, and reboot.
          # ---------------------------------------------------------------------------
          rlLog "Installing kmod-amdgpu"
          # Enable RCMTOOLS repo so brew (Koji) can be installed
          rlRun "dnf config-manager --add-repo http://download.devel.redhat.com/rel-eng/RCMTOOLS/rcm-tools-rhel-9-baseos.repo"
          rlRun "dnf -y install brewkoji"
          # Pull all artifacts from the Brew task (kernel + kmod RPM)
          rlRun "brew download-task ${BREW_TASK_ID}"
          # Verify artifacts were downloaded
          RPM_COUNT=$(ls -1 *.rpm 2>/dev/null | wc -l)
          rlRun "[ ${RPM_COUNT} -gt 0 ]" 0 "Artifacts downloaded"
          # Locate the kmod-amdgpu*.rpm we just downloaded (arch-specific name)
          KMOD_RPM=$(find . -maxdepth 1 -regextype egrep -regex './kmod-amdgpu-.*\.(x86_64|aarch64|ppc64le|s390x)\.rpm$' -print -quit)
          rlRun "[ -n \"$KMOD_RPM\" ]" 0 "Found kmod package $KMOD_RPM"
          # Extract kernel release (including arch) from the rpm filename so it matches $(uname -r)
          # Example: kmod-amdgpu-5.14.0-570.27.1.el9_6.x86_64.rpm → 5.14.0-570.27.1.el9_6.x86_64
          KMOD_KERNEL_RELEASE=$(basename "$KMOD_RPM" | sed -E 's/^kmod-amdgpu-(.*)\.(x86_64|aarch64|ppc64le|s390x)\.rpm$/\1.\2/')
          # And get the version without the arch for installing kernel packages
          KMOD_KERNEL_VERSION=$(echo "$KMOD_KERNEL_RELEASE" | sed -E 's/\.(x86_64|aarch64|ppc64le|s390x)$//')
          HOST_ARCH=$(uname -m)

          # Validate distro tag (elX) matches the running system; fail early if mismatched
          RHEL_MAJOR=$(rpm --eval '%{?rhel}')
          if ! echo "$KMOD_KERNEL_RELEASE" | grep -q ".el${RHEL_MAJOR}_"; then
              rlFail "kmod targets different distro than host: host el${RHEL_MAJOR}, kmod '${KMOD_KERNEL_RELEASE}'"
              exit 1
          fi

          # Export for current script context and persist for post-reboot run
          export KMOD_KERNEL_RELEASE
          echo "$KMOD_KERNEL_RELEASE" > /var/tmp/kmod_kernel_release

          # Ensure required kernel RPMs (host arch) are available; fetch via Brew if missing, then install
          rlLog "Installing kernel for ${KMOD_KERNEL_VERSION} (${HOST_ARCH})"
          KERNEL_RPMS_GLOB="./kernel-*-${KMOD_KERNEL_VERSION}.${HOST_ARCH}.rpm"
          if ! compgen -G "$KERNEL_RPMS_GLOB" > /dev/null; then
              rlLog "Kernel RPMs not present locally; fetching from Brew build kernel-${KMOD_KERNEL_VERSION}"
              rlRun "brew download-build kernel-${KMOD_KERNEL_VERSION}"
          fi
          rlRun "compgen -G '$KERNEL_RPMS_GLOB' > /dev/null" 0 "Kernel RPMs located"
          rlRun "dnf -y install $KERNEL_RPMS_GLOB"

          # Install the kmod package itself
          rlLog "Installing kmod package ${KMOD_RPM}"
          rlRun "dnf -y install ${KMOD_RPM}"

          # Set the just-installed kernel as the default for the next boot
          if grubby --info=ALL | grep -q "/boot/vmlinuz-${KMOD_KERNEL_RELEASE}"; then
              rlRun "grubby --set-default /boot/vmlinuz-${KMOD_KERNEL_RELEASE}"
          else
              rlLog "Could not find vmlinuz for new kernel ${KMOD_KERNEL_RELEASE}; skipping grubby default set"
          fi

          sync
          tmt-reboot || rstrnt-reboot || rhts-reboot || reboot
        else
          rlLog "Setup phase post-reboot: skipping provisioning"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        # Restore persisted kernel release if this is the post-reboot run
        if [[ -z "$KMOD_KERNEL_RELEASE" && -f /var/tmp/kmod_kernel_release ]]; then
            KMOD_KERNEL_RELEASE=$(cat /var/tmp/kmod_kernel_release)
        fi

        # Run verification only after reboot occurred
        if [ -n "${RSTRNT_REBOOTCOUNT}" ] && [ "${RSTRNT_REBOOTCOUNT}" -ge "1" ]; then
            rlRun "[ \"$(uname -r)\" = \"$KMOD_KERNEL_RELEASE\" ]" \
                  0 "Kernel release matches expected $KMOD_KERNEL_RELEASE"
        else
            rlLog "Verification deferred until after reboot"
        fi
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
