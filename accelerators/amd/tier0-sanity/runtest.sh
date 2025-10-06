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

# Include environments
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Include the AMD accelerators library
CDIR=$(dirname "${FILE}")
. "${CDIR}/../include.sh"    || exit 1


rlJournalStart
    rlPhaseStartSetup "Setup Environment"
        AmdROCmSetUp
        rlAssertRpm "kernel"
    rlPhaseEnd

    rlPhaseStartTest "Check and reload amdgpu module"

        if [[ -n $AMDGPU_MODULE_TEST ]]; then
            rlLog "Testing AMDGPU module"
            rlRun "lsmod | grep -q '^amdgpu'" 0,1
            if [[ $? -eq 0 ]]; then
                rlLog "amdgpu module is loaded. Unloading..."
                rlRun "modprobe -r amdgpu"
            else
                rlLog "amdgpu module is not loaded."
            fi
            rlRun "MODPROBE_OUTPUT=\$(modprobe -v amdgpu 2>&1)" 0 "Load amdgpu module with verbose output"
            rlLog "modprobe output: $MODPROBE_OUTPUT"
            rlRun "echo \"\$MODPROBE_OUTPUT\" | grep -E \"/lib/modules/\$(uname -r)/extra/amdgpu.ko(\\.(xz|zst|gz))?\"" \
                0 "Verify amdgpu module path is under extra/ and matches current kernel"

            rlRun "lsmod | grep -q '^amdgpu'" 0 "Ensure amdgpu is now loaded"
        fi

        rlLog "rocminfo check"
        rlRun "rocminfo"
        rlLog "amd-smi checks"
        rlRun "amd-smi list"
        rlRun "amd-smi static"
        rlRun "amd-smi firmware"
        rlRun "amd-smi monitor"
    rlPhaseEnd

    rlPhaseStartCleanup "Cleanup Environment"
        AmdROCmCleanUp
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText
