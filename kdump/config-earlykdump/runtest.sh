#!/bin/sh

# Copyright (C) 2008 Xiaowu Wu <xiawu@redhat.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh

EnableEarlykdump() {
    DisableAVCCheck

    if [ ! -f "${K_REBOOT}" ]; then
        # Backup system initrd
        cp "${INITRD_IMG_PATH}" "${INITRD_IMG_PATH}.bk"

        # It assumes the kdump img is ready in previous steps
        # Rebuild system initamfs with early kdump support
        LogRun "dracut --force --add earlykdump"
        [ "$?" -ne 0 ] && MajorError "Failed to build initramfs with early kdump susport."

        # Add rd.earlykdump in kernel command line
        UpdateKernelOptions "rd.earlykdump"

        # Reboot system
        touch "${K_REBOOT}"
        sync;sync;sync
        RhtsReboot
    else
        rm -f "${K_REBOOT}"

        # Validate if early-kdump is enabled.
        local succeed=true
        journalctl -b | grep "early-kdump is enabled"
        [ "$?" -ne 0 ] && succeed=false
        journalctl -b | grep "kexec: loaded early-kdump kernel"
        [ "$?" -ne 0 ] && succeed=false

        # Submit journal log no matter succeed or not.
        journalctl -b > "${K_TESTAREA}/journal.log"
        RhtsSubmit "${K_TESTAREA}/journal.log"

        [ "$succeed" = "false" ] && {
            MajorError "Failed to enable early kdump. Please check journal.log."
        }
    fi
}

# --- start ---
Multihost "EnableEarlykdump"
