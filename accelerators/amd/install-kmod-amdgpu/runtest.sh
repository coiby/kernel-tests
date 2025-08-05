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

    rlPhaseStartTest

        # First boot after provision?  Install kmod then reboot so the new kernel, if any, is picked up.
        if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq "0" ]; then
          # ---------------------------------------------------------------------------
          # 1. Enable RCM tools repo so we can use rhpkg / brewkoji.
          # 2. Download all artifacts from the specified Brew task ID.
          # 3. Pick the first kmod-amdgpu RPM found, extract the kernel-release part
          #    from its filename, save it in $KMOD_KERNEL_RELEASE, and install it.
          #    Example filename → kernel release extracted:
          #      kmod-amdgpu-5.14.0-570.27.1.el9_6.x86_64.rpm ⇢ 5.14.0-570.27.1.el9_6
          # ---------------------------------------------------------------------------
          rlLog "Installing kmod-amdgpu"
          # Enable RCMTOOLS repo so rhpkg / brewkoji can be installed
          rlRun "dnf config-manager --add-repo http://download.devel.redhat.com/rel-eng/RCMTOOLS/rcm-tools-rhel-9-baseos.repo"
          rlRun "dnf -y install rhpkg brewkoji"
          # Pull all artifacts from the Brew task (kernel + kmod RPM)
          rlRun "brew download-task ${BREW_TASK_ID}"
          # Locate the kmod-amdgpu*.rpm we just downloaded (arch-specific name)
          KMOD_RPM=$(find . -maxdepth 1 -regextype egrep -regex './kmod-amdgpu-.*\.(x86_64|aarch64|ppc64le|s390x)\.rpm$' -print -quit)
          rlRun "[ -n \"$KMOD_RPM\" ]" 0 "Found kmod package $KMOD_RPM"
          # Extract kernel release (including arch) from the rpm filename so it matches $(uname -r)
          # Example: kmod-amdgpu-5.14.0-570.27.1.el9_6.x86_64.rpm → 5.14.0-570.27.1.el9_6.x86_64
          KMOD_KERNEL_RELEASE=$(basename "$KMOD_RPM" | sed -E 's/^kmod-amdgpu-(.*)\.(x86_64|aarch64|ppc64le|s390x)\.rpm$/\1.\2/')
          # Export for current script context and persist for post-reboot run
          export KMOD_KERNEL_RELEASE
          echo "$KMOD_KERNEL_RELEASE" > /var/tmp/kmod_kernel_release
          # Install the rpm
          rlRun "dnf -y install $KMOD_RPM"

          sync
          tmt-reboot || rstrnt-reboot || rhts-reboot
        fi

        # ---------------------------------------------------------------------------
        # 1. Verify that the kmod we installed targets the currently running kernel by
        #    comparing $KMOD_KERNEL_RELEASE (captured during install) with $(uname -r).
        #    If they match, we know the correct version is active.
        # ---------------------------------------------------------------------------
        # Restore persisted kernel release if this is the post-reboot run
        if [[ -z "$KMOD_KERNEL_RELEASE" && -f /var/tmp/kmod_kernel_release ]]; then
            KMOD_KERNEL_RELEASE=$(cat /var/tmp/kmod_kernel_release)
        fi

        # 1. kernel release matches
        rlRun "[ \"$(uname -r)\" = \"$KMOD_KERNEL_RELEASE\" ]" \
              0 "Kernel release matches expected $KMOD_KERNEL_RELEASE"
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
