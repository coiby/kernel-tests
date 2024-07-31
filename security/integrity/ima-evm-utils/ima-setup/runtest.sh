#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/integrity/ima-evm-utils/ima-setup
#   Description: Test for ima-setup script(note: Test will change system IMA setup, therfore might effect remaining test runs. it should run as the last test)
#   Author: Dennis Li <denli@redhat.com>
#
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
TmpDir=$(pwd)/tmp

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlRun -l "evmctl --version"
        current_version=$(evmctl --version | awk '{print $NF}')
        IFS='.' read -r current_major current_minor <<< "$current_version"
        current_major=$((current_major))
        current_minor=$((current_minor))
        if (( current_major < 1 )) || { (( current_major == 1 )) && (( current_minor < 5 )); }; then
            rlLog "[SKIP] Skipping test for evmctl versions < 1.5"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            exit 0
        fi
    rlPhaseEnd

    rlPhaseStartTest "setup IMA policy test"
       if ! [[ -e $TmpDir/reboot ]]; then
        rlRun "cat /etc/ima/ima-policy" 1 "No IMA policy loaded before setup"
        rlRun -l "ima-setup --policy=/usr/share/ima/policies/02-keylime-remote-attestation" 0 "Runing the setup script"
        rlRun -l "getfattr -d -m security.ima /usr/bin/bash | grep security.ima" 0 "File has been signed with security.ima"
        rlRun "mkdir $TmpDir" 0 "Creating tmp directory"
        rlRun "touch $TmpDir/reboot" && sync
        rhts-reboot
       else
        rlRun "cat /etc/ima/ima-policy" 0 "Checking if IMA policy is still loaded after reboot"
        rlRun -l "keyctl show %:.ima | grep IMA" 0 "IMA release key sucessfully loaded in keyring"
       fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "dmesg > /tmp/dmesg.out" 0 "Print dmesg info"
        rlFileSubmit /tmp/dmesg.out
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
