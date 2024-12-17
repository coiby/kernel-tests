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

# Include cki library
# . ../../cki_lib/libcki.sh || exit 1

NVIDIA_DEVFILES="nvidia0 nvidiactl nvidia-uvm nvidia-uvm-tools"
NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

TEST_GPU="TeslaT4"

rlJournalStart

    rlPhaseStartSetup

        case ${TEST_GPU} in
            TeslaT4)
                rlLog "Smoke tests for NVIDIA Tesla T4"
                NVIDIA_GPU_NAME="Tesla T4"
                NVIDIA_GPU_MEMORY_TOTAL="15360 MiB"
                NVIDIA_GPU_POWER_LIMIT="70.00 W"
                NVIDIA_GPU_ECC_STATE="Enabled"
                ;;
            RTX3060Ti)
                rlLog "Smoke tests for NVIDIA GeForce RTX 3060 Ti"
                NVIDIA_GPU_NAME="NVIDIA GeForce RTX 3060 Ti"
                NVIDIA_GPU_MEMORY_TOTAL="8192 MiB"
                NVIDIA_GPU_POWER_LIMIT="200.00 W"
                NVIDIA_GPU_ECC_STATE="[N/A]"
                ;;
            *)
                rlLog "Specified GPU is not supported by this test"
                exit 1
                ;;
        esac

    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Testing OpenRM driver"

        # Check modules load
        rlLog "Check nvidia modules"
        for MODULE_NAME in ${NVIDIA_MODULES}
        do
            rlRun "modprobe ${MODULE_NAME}"
            rlRun "lsmod | cut -d' ' -f1 | grep -q \^${MODULE_NAME}\$"

        done

        # Check nvidia-smi works. This shoud generate some device files
        rlRun "nvidia-smi"

        # Check device files
        for DEVFILE in ${NVIDIA_DEVFILES}
        do
            rlAssertExists "/dev/${DEVFILE}"
            rlRun "test -c /dev/${DEVFILE}"
        done

        # GPU name check
        rlLog "GPU name"
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        rlAssertEquals "GPU name" "${NVIDIA_GPU_NAME}" "${GPU_NAME}"

        # GPU various GPU queries with nvidia-smi
        rlLog "Memory information"
        MEMORY_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader)
        rlAssertEquals "Card memory total" "${NVIDIA_GPU_MEMORY_TOTAL}" "${MEMORY_TOTAL}"
        rlRun "nvidia-smi --query-gpu=memory.total,memory.free,memory.used --format=csv,noheader"

        rlLog "Power usage and temperature"
        POWER_LIMIT=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader)
        rlAssertEquals "Card power limit" "${NVIDIA_GPU_POWER_LIMIT}" "${POWER_LIMIT}"
        rlRun "nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit --format=csv,noheader"

        rlLog "ECC state"
        ECC_STATE=$(nvidia-smi --query-gpu=ecc.mode.current --format=csv,noheader)
        rlAssertEquals "ECC state" "${NVIDIA_GPU_ECC_STATE}" "${ECC_STATE}"
    rlPhaseEnd

rlJournalEnd

rlJournalPrintText

