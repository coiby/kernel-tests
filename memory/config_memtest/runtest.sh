#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Test checkes the verification of the config_memtest variable enablement
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
# Include the BeakerLib environment and libCKI function helper.
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../cki_lib/libcki.sh
. ../../cmdline_helper/libcmd.sh
# Define boot config file path in case of an ostree
if cki_is_ostree_booted; then
    BOOT_CONFIG=/usr/lib/ostree-boot/config-$(uname -r)
else
    BOOT_CONFIG=/boot/config-$(uname -r)
fi

rlJournalStart
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
        rlPhaseStartSetup "Adding memtest=1 variable in "
            rlShowRunningKernel
            rlRun "change_cmdline 'memtest=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
    if [ "${REBOOTCOUNT}" -eq 1 ]; then
        rlPhaseStartTest "Check that config_memtest is enable and dmseg log for the memtest result"
            DMESG_TEMP_FILE="/tmp/dmesg_temp.txt"
            dmesg > "$DMESG_TEMP_FILE"
            rlAssertGrep "CONFIG_MEMTEST=y" "${BOOT_CONFIG}" -i
            rlAssertGrep "early_memtest" "${DMESG_TEMP_FILE}" -i
        rlPhaseEnd
        rlPhaseStartCleanup
            rm -f "$DMESG_TEMP_FILE"
            rlRun "change_cmdline '-memtest=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
