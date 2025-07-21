#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/audit/RHEL-90106
#   Description: Test for RHEL-90106 audit functionality
#   Author: Dennis Li <denli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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


rlJournalStart "rhel-90106"

    rlPhaseStartSetup
        rlShowRunningKernel

        # Start audit daemon if not running
        rlRun "systemctl start auditd" 0,1 "Starting audit daemon"
        rlRun "systemctl is-active auditd" 0 "Verify auditd is active"

        # Clear any existing audit rules and logs
        rlRun "auditctl -D" 0,1 "Clear existing audit rules"
        rlRun "service auditd rotate" 0,1 "Rotate audit logs"

        # Set up audit rule to watch /tmp
        rlRun "auditctl -w /tmp" 0 "Set up audit watch on /tmp"
        rlRun "auditctl -l" 0 "List current audit rules"
    rlPhaseEnd

    rlPhaseStartTest
        rlLogInfo "Starting RHEL-90106 audit test for directory operations"

        # Create test directory
        rlRun "mkdir /tmp/foo" 0 "Create test directory /tmp/foo"

        # Remove test directory
        rlRun "rm -r /tmp/foo/" 0 "Remove test directory /tmp/foo"

        # Wait a moment for audit log to be written
        rlRun "sleep 2" 0 "Wait for audit log to be written"

        # Check audit logs for PATH entries
        rlRun "ausearch -i | grep PATH | tail -3 > audit_output.txt" 0 "Get recent PATH entries from audit log"
        rlRun "cat audit_output.txt" 0 "Display audit output"

        # Verify that the audit log contains proper path names, not "(null)"
        rlRun "grep 'name=/tmp/foo' audit_output.txt" 0 "Check that /tmp/foo path is properly recorded"

    rlPhaseEnd

    rlPhaseStartCleanup
        # Clean up audit rules
        rlRun "auditctl -W /tmp" 0,1 "Remove audit watch on /tmp"
        rlRun "rm -f audit_output.txt" 0 "Clean up output files"
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd