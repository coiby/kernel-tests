#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/ipmi/hotmod
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
export TEST="/kernel/ipmi/hotmod"

# Set hotmod commands
if rlIsRHEL "<8"; then
    ipmiparam=$(cat /proc/ipmi/0/params)
else
    ipmiparam=$(cat /sys/devices/platform/ipmi_bmc.0/ipmi0/ipmi/ipmi0/device/params)
fi
hotmodrm="remove,$ipmiparam"
hotmodadd="add,$ipmiparam"

rlJournalStart
# Exit if not ipmi compatible
    rlPhaseStartSetup
        rlRun -l "dmidecode --type 38 > /tmp/dmidecode.log"
            if grep -i ipmi /tmp/dmidecode.log ; then
                rlPass "Moving on, host is ipmi compatible"
            else
                rlPhaseStart WARN "host is not ipmi compatible"
                rlFail "Exiting, host is not ipmi compatible"
            exit 1
                rlPhaseEnd
            fi
        # Install OpenIPMI
        rlRun -l "yum install -y OpenIPMI"
        # Verify ipmi service starts successfully
        rlServiceStart ipmi
        # Verify ipmi device is displayed
        rlRun -l "ls -l /dev/ipmi0"
    rlPhaseEnd

    # IPMI: IPMI Driver panics during rmmod command if hotmod/remove operation
    # has been done before (BZ 1135910)
    rlPhaseStartTest
        rlRun -l "echo $hotmodrm >  /sys/module/ipmi_si/parameters/hotmod"
        sleep 5
        if pgrep "kipmi"; then
            rlFail "kipmi process still running"
            exit 1
        else
            rlLogInfo "kipmi process killed successfully"
        fi
        if lsmod | grep '^power_meter'; then
            rlRun -l "rmmod power_meter"
        fi
        if lsmod | grep acpi_ipmi; then
            rlRun -l "rmmod acpi_ipmi ipmi_si"
        else
           rlRun -l "rmmod ipmi_si"
        fi
        rlRun -l "grep -i ipmi /var/log/messages > /tmp/remove_error.log"
        rlAssertNotGrep "error|fail|warn" /tmp/remove_error.log -i
    rlPhaseEnd

    # IPMI Driver panics during hotmod/add operation if hotmod/remove operation has been done
    # for it before (BZ 1139464) 
    rlPhaseStartTest
        rlRun -l "modprobe ipmi_si"
        rlRun -l "echo $hotmodrm > /sys/module/ipmi_si/parameters/hotmod"
        sleep 5
        if pgrep "kipmi"; then
            rlFail "kipmi process still running"
            exit 1
        else
            rlLogInfo "kipmi process killed successfully"
        fi
        rlRun -l "echo $hotmodadd >  /sys/module/ipmi_si/parameters/hotmod" 
        sleep 5
        if pgrep "kipmi"; then
            rlLogInfo "kipmi process is running"
        else
            rlFail "kipmi process isn't running"
        fi
        rlRun -l "grep -i ipmi /var/log/messages > /tmp/add_error.log"
        rlAssertNotGrep "error|fail|warn" /tmp/add_error.log -i
    rlPhaseEnd

rlJournalEnd
# Print the test report
rlJournalPrintText
