#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/integrity/ima-evm-utils/rhel-105771
#   Description: Test for RHEL-105771 ima-evm-utils functionality
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

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        # Verify installation
        rlRun "rpm -ql ima-evm-utils" 0 "List ima-evm-utils files"
        rlRun "evmctl --version" 0 "Check evmctl version"
    rlPhaseEnd

    rlPhaseStartTest "RHEL-105771 ima-evm-utils test"
        # Detect RHEL version and set appropriate key path
        rhel_version=$(grep -o 'release [0-9]*' /etc/redhat-release | awk '{print $2}')

        if [ -z "$rhel_version" ] || [ "$rhel_version" -lt 9 ]; then
            rlLogError "Unable to detect RHEL version or unsupported version: $rhel_version"
            rlFail "Test requires RHEL 9 or later"
            exit 1
        fi

        ima_key_path="/etc/keys/ima/redhatimarelease-${rhel_version}.der"
        rlLogInfo "Using IMA key path: $ima_key_path for RHEL $rhel_version"

        # Verify the IMA key exists
        rlRun "test -f $ima_key_path" 0 "Verify IMA release key exists"

        # Run ima-add-sigs to ensure no files fail signature check
        rlRun "ima-add-sigs --reinstall_threshold=1000" 0 "Run ima-add-sigs with reinstall threshold"

        # Check for files that fail signature verification
        rlLogInfo "Checking for files with failed IMA signature verification"
        failed_count=$(find / -fstype xfs -type f -uid 0 2>/dev/null | while read i; do
            if [ -e "$i" ] && getfattr -m security.ima -d -e hex "$i" 2>/dev/null | grep -qs security.ima=0x03 && ! evmctl ima_verify -k "$ima_key_path" "$i" 2>/dev/null; then
                echo "$i";
            fi;
        done 2>/dev/null | wc -l)

        rlLogInfo "Number of files with failed signature verification: $failed_count"
        rlRun "test $failed_count -eq 0" 0 "Verify no files fail signature check"

        if [ "$failed_count" -gt 0 ]; then
            rlLogError "Found $failed_count files with signature verification failures"
            # Log some examples of failed files for debugging
            rlLogInfo "Examples of files with failed verification:"
            find / -fstype xfs -type f -uid 0 2>/dev/null | head -100 | while read i; do
                if [ -e "$i" ] && getfattr -m security.ima -d -e hex "$i" 2>/dev/null | grep -qs security.ima=0x03 && ! evmctl ima_verify -k "$ima_key_path" "$i" 2>/dev/null; then
                    rlLogError "Failed verification: $i"
                fi;
            done 2>/dev/null | head -10
        fi

    rlPhaseEnd

    rlPhaseStartCleanup
        rlLogInfo "Test cleanup completed"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
