#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        grubby --info=DEFAULT
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "fips-mode-setup --check"
        rlRun "fips-mode-setup --is-enabled" && rlPass "FIPS mode is enabled" && exit 0
        [[ -e /tmp/enable_fips_attempted ]] && rlDie "Failed to enable FIPS"
        touch /tmp/enable_fips_attempted && sync
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "fips-mode-setup --enable --no-bootcfg"
            kernel_args=$(fips-mode-setup --enable --no-bootcfg | awk -F\" '/fips=1/ {print $2}')
            kernel_current=$(grubby --info=DEFAULT | awk -F\" '/kernel=/ {print $2}')
            grubby --update-kernel="${kernel_current}" --args="${kernel_args}"
        else
            rlRun "fips-mode-setup --enable"
        fi
        rlRun "rhts-reboot"
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
