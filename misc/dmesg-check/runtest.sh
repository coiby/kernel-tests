#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/dmesg-check
#   Description: Check dmesg log after boot for any bugs. We also check
#		 for warnings and errors.
#   Author: William Gomeringer <wgomerin@redhat.com>
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

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/share/rhts-library/rhtslib.sh

# Some things to look for
#
# grep -w bug /var/log/dmesg
# grep -i error /var/log/dmesg
# grep -i warning /var/log/dmesg

PACKAGE="kernel"
LOG="check_output.log"

bug_check()
{
        if ! rlRun "grep -w BUG /var/log/dmesg" 1 ; then
                rlLog "Bug found during boot. Please open a bugzilla to report it."
        else
                rlLog "No bugs found during boot"
        fi
}

error_check()
{
        if ! rlRun "grep -i error /var/log/dmesg" 1 ; then
                rlLogWarning "There were some errors during boot. Please check /var/log/dmesg, and check_output.log in the test directory, to determine whether or not a bug should be opened."
        else
                rlLog "No errors found during boot"
        fi
}

warning_check()
{
        if ! rlRun "grep -i warning /var/log/dmesg" 1 ; then
                rlLogWarning "There were some warnings during boot. Please check /var/log/dmesg, and check_output.log in the test directory, to determine whether or not a bug should be opened."
        else
                rlLog "No warnings found during boot"
        fi
}

check_output()
{
	grep -w BUG /var/log/dmesg > $LOG
	grep -i error /var/log/dmesg >> $LOG
	grep -i warning /var/log/dmesg >> $LOG
}

rlJournalStart
        rlPhaseStartSetup
                rlAssertRpm $PACKAGE
                rlShowRunningKernel
        rlPhaseEnd

        rlPhaseStartTest
                bug_check
                error_check
                warning_check
                check_output
        rlPhaseEnd

        rlPhaseStartCleanup
                rlFileSubmit $LOG
        rlPhaseEnd

rlJournalPrintText
rlJournalEnd
