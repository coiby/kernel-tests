#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

if [ "$1" != "initramfs" ] && [ "$1" != "rootfs" ]; then
    echo "Usage: $0 {initramfs|rootfs}"
    exit 1
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
if [ "${TMT_TEST_RESTART_COUNT}" -eq 0 ]; then
    rlPhaseStartTest Inject failure
        if  [ "$1" == "initramfs" ]; then
            rlLog "*** Corrupting initramfs ***"
            rlRun "dd if=/dev/zero of=/boot/initramfs-$(uname -r).img bs=1 count=100 conv=notrunc"
            rlRun "aboot-update -i /boot/initramfs-$(uname -r).img $(uname -r)"
        elif [ "$1" == "rootfs" ]; then
            rlLog "*** Corrupting rootfs mount point ***"
            if grep -qi SA8775P /sys/devices/soc0/machine; then
                rlRun "aboot-update -c \"\$(cat /proc/cmdline | sed 's/sde38/sde0/g')\" $(uname -r)"
            elif grep -qi "Renesas Spider CPU and Breakout boards based on r8a779f0" /sys/devices/soc0/machine; then
                rlRun "aboot-update -c \"\$(cat /proc/cmdline | sed 's/system_a/system_c/g')\" $(uname -r)"
            fi
        fi
        rlRun "aboot-deploy -l aboot-$(uname -r).img"
        rlRun "systemctl reboot"
    rlPhaseEnd
elif [ "${TMT_TEST_RESTART_COUNT}" -ge 1 ]; then
    rlPhaseStartTest Check after reboot
        rlFail "System should keep rebooting."
    rlPhaseEnd
fi
rlJournalEnd
rlJournalPrintText
