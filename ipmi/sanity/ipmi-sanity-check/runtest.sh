#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/ipmi/sanity/ipmi-sanity-check
#   Description: IPMI Sanity Check
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
export TEST="/kernel/ipmi/sanity/ipmi-sanity-check"

# Exit if not ipmi compatible
rlJournalStart
    rlPhaseStartTest
        rlRun -l "dmidecode --type 38 > /tmp/dmidecode.log"
            if grep -i ipmi /tmp/dmidecode.log ; then
                rlPass "Moving on, host is ipmi compatible"
            else
                rlPhaseStart WARN "host is not ipmi compatible"
                    rlFail "Exiting, host is not ipmi compatible"
                    exit 1
                rlPhaseEnd
            fi
    rlPhaseEnd

# Install ipmi related packages
    rlPhaseStartTest
        rlRun -l "yum install -y ipmitool freeipmi OpenIPMI"
        rlRun "cat /var/log/messages | grep -i ipmi > /tmp/error.log"
        rlAssertNotGrep "error|fail|warn" /tmp/error.log -i
    rlPhaseEnd

# remove any existing drivers first
    rlPhaseStartTest
        modprobe -r ipmi_watchdog
        modprobe -r ipmi_devintf
        modprobe -r ipmi_poweroff
        modprobe -r power_meter
        modprobe -r acpi_ipmi
        modprobe -r ipmi_si
        modprobe -r ipmi_ssif
        modprobe -r ipmi_msghandler

    rlPhaseEnd

# Load each ipmi driver, verify the driver loaded successfully
    rlPhaseStartTest
        modprobe ipmi_watchdog
        lsmod | grep ipmi_watchdog
        modprobe ipmi_devintf
        lsmod | grep ipmi_devintf
        modprobe ipmi_poweroff
        lsmod | grep ipmi_poweroff
        modprobe ipmi_si
        lsmod | grep ipmi_si
        modprobe ipmi_ssif
        lsmod | grep ipmi_ssif
        modprobe ipmi_msghandler
        lsmod | grep ipmi_msghandler
    rlPhaseEnd

# ToDo re-enable after bz1648133 is resolved
# Verify ipmi service starts successfully
#    rlPhaseStartTest
#        rlServiceStart ipmi
#    rlPhaseEnd

# Verify ipmi device is displayed
    rlPhaseStartTest
        rlRun -l "ls -l /dev/ipmi0"
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
