#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/OpenIPMI/ipmitool
#   Description: IPMItool smoke test
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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
export TEST="/kernel/OpenIPMI/ipmitool"

rlJournalStart
# Exit if not ipmi compatible
    rlPhaseStartSetup
        rlRun -l "dmidecode --type 38 > /tmp/dmidecode.log"
            if grep -i ipmi /tmp/dmidecode.log ; then
                rlPass "Moving on, host is ipmi compatible"
            else
                rlPhaseStart WARN "host is not ipmi compatible"
                rlLogWarning "Exiting, host is not ipmi compatible"
            exit 1
                rlPhaseEnd
            fi
    rlPhaseEnd

# Check that ipmitool rpm is installed
    rlPhaseStartTest
        if ! rlCheckRpm ipmitool; then
            yum -y install ipmitool
            rlAssertRpm ipmitool
        fi
    rlPhaseEnd


# Check that OpenIPMI rpm is installed
    rlPhaseStartTest
        if ! rlCheckRpm OpenIPMI; then
           yum -y install OpenIPMI
           rlAssertRpm OpenIPMI
        fi
    rlPhaseEnd

# ToDo disable until bz 1648133 is resolved
# start and enable ipmi
#    rlPhaseStartTest
#        rlServiceStart ipmi
#    rlPhaseEnd

    # Execute various ipmitool commands in a loop
    rlPhaseStartTest
    rlRun -l "TEMP_FILE=$(mktemp)" 0
        rlRun -l "ipmitool sdr elist | cut -c 31-36 | sort | uniq > ${TEMP_FILE}" 0
	for I in $(cat "${TEMP_FILE}") ; do
            # Known issue, see BZ 1627526
            rlRun -l "ipmitool sdr entity $I" 0,1
        done
        rlRun -l "rm -f ${TEMP_FILE}" 0

        rlRun -l "ipmitool sdr dump ${TEMP_FILE}" 0
        rlRun -l "rm -f ${TEMP_FILE}" 0

        rlRun -l "ipmitool sensor" 0
        rlRun -l "ipmitool -v sensor" 0

        rlRun -l "ipmitool fru" 0

        rlRun -l "ipmitool sel clear" 0
            sleep 3
        rlRun -l "ipmitool event 1" 0
        rlRun -l "ipmitool sel" 0
        rlRun -l "ipmitool sel list" 0
        rlRun -l "ipmitool sel elist" 0
        rlRun -l "ipmitool sel time" 0
        rlRun -l "ipmitool sel time get" 0
        rlRun -l "ipmitool sel save ${TEMP_FILE}" 0

        rlRun -l "ipmitool event file ${TEMP_FILE}" 0
        rlRun -l "rm -f ${TEMP_FILE}" 0

        rlRun -l "ipmitool sel writeraw ${TEMP_FILE}" 0
        rlRun -l "ipmitool sel readraw ${TEMP_FILE}" 0
        rlRun -l "rm -f ${TEMP_FILE}" 0

        rlRun -l "ipmitool sol" 0
        rlRun -l "ipmitool isol" 0
        rlRun -l "ipmitool session" 0
        rlRun -l "ipmitool sunoem" 0
        rlRun -l "ipmitool kontronoem nextboot" 1
        rlRun -l "ipmitool picmg" 0
        rlRun -l "ipmitool fwum status" 0,1
        rlRun -l "ipmitool firewall" 0
        rlRun -l "ipmitool firewall info" 0

    rlPhaseEnd

    # Verify no errors are aseen in the logs
    rlPhaseStartTest
        rlRun "journalctl -b -p err | grep ipmi  > /tmp/error.log" 0,1
        rlRun "cat /tmp/error.log"
        rlAssertNotGrep "error|fail|warn" /tmp/error.log -i
    rlPhaseEnd
rlJournalEnd

 rlJournalPrintText
rlJournalEnd
