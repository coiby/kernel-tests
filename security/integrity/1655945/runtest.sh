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
        rlRun -l "evmctl --version"
        current_version=$(evmctl --version | awk '{print $NF}')
        IFS='.' read -r current_major current_minor <<< "$current_version"
        current_major=$((current_major))
        current_minor=$((current_minor))
        if (( current_major > 1 )) || { (( current_major == 1 )) && (( current_minor > 4 )); }; then
            rlLog "[SKIP] Skipping test for evmctl versions > 1.4"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            exit 0
        fi
        rlRun "openssl genrsa -out rsa_private.pem 1024"
        rlRun "openssl rsa -pubout -in rsa_private.pem -out rsa_public.pem"
        rlRun "keyctl show"
        keyring="@u"
        keyctl show | grep "_uid" || keyring="@s"
    rlPhaseEnd

    rlPhaseStartTest "ima"
        rlRun "keyctl newring _ima $keyring | tee ima.id"
        rlRun "keyctl show"
        rlRun "evmctl import --rsa rsa_public.pem $(cat ima.id) | tee key.id"
        rlRun "keyctl show"
        rlRun "keyctl show | grep $(cat key.id) | tee keyctl.output"
        rlAssertGrep "\w{14,16}" keyctl.output -E
        rlAssertNotGrep "Binary file" keyctl.output -i
    rlPhaseEnd

    rlPhaseStartTest "evm"
        rlRun "keyctl newring _evm $keyring | tee evm.id"
        rlRun "keyctl show"
        rlRun "evmctl import --rsa rsa_public.pem $(cat evm.id) | tee key.id"
        rlRun "keyctl show"
        rlRun "keyctl show | grep $(cat key.id) | tee keyctl.output"
        rlAssertGrep "\w{14,16}" keyctl.output -E
        rlAssertNotGrep "Binary file" keyctl.output -i
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "keyctl clear $(cat ima.id)"
        rlRun "keyctl clear $(cat evm.id)"
        rlRun "keyctl revoke $(cat ima.id)"
        rlRun "keyctl revoke $(cat evm.id)"
        rlRun "rm -f *.id keyctl.output"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
