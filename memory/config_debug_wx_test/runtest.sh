#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Test checks if the kernel type is generic or debug and then checks the next:
#   In case that the kernel is generic it verifies that CONFIG_DEBUG_WX is not configured and not shown in the dmesg
#   In case that the kernenl is debug it verifies that CONFIG_DEBUG_WX is configured and results and it shown in the dmesg
#   Author: Michael Menasherov <mmenashe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 3.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Include the BeakerLib environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
# Define boot config file path in case of an ostree
if [[ -e /run/ostree-booted ]]; then
    BOOT_CONFIG=/usr/lib/ostree-boot/config-$(uname -r)
else
    BOOT_CONFIG=/boot/config-$(uname -r)
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        DMESG_TEMP_FILE="/tmp/dmesg_temp.txt"
        dmesg > "$DMESG_TEMP_FILE"
    rlPhaseEnd

    rlPhaseStartTest "Check CONFIG_DEBUG_WX status and dmseg log based on kernel type"
        if [[ $(uname -r) =~ "debug" ]]; then
            rlAssertGrep "CONFIG_DEBUG_WX=y" "${BOOT_CONFIG}" -i
            rlAssertGrep "Checked W+X mappings" "${DMESG_TEMP_FILE}" -i
        else
            rlAssertNotGrep "CONFIG_DEBUG_WX=y" "${BOOT_CONFIG}" -i
            rlAssertNotGrep "Checked W+X mappings" "${DMESG_TEMP_FILE}" -i
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rm -f "$DMESG_TEMP_FILE"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

