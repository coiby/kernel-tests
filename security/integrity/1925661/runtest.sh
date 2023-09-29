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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        grubby --info=DEFAULT
#        case `uname -m` in
#            "ppc64le") export cer_file="kernel-signing-ppc.cer" ;;
#            "s390x") export cer_file="kernel-signing-s390.cer" ;;
#            "s390x") exit 0 ;;
#            "x86_64") exit 0 ;;
#            "aarch64") exit 0 ;;
#            *) exit 1 ;;
#        esac
        if [[ $(uname -m) != "ppc64le" ]]; then
            echo "[SKIP] support ppc64le only"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            rlJournalEnd ; rlJournalPrintText
            exit 0
        fi
        export cer_file="kernel-signing-ppc.cer"
        rlRun "yum install -y keyutils"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "keyctl show %:.builtin_trusted_keys | tee /tmp/.builtin_trusted_keys"
        rlAssertGrep "asymmetric: Red Hat Secure Boot" /tmp/.builtin_trusted_keys
        rlRun "ls -l /usr/share/doc/kernel-keys/`uname -r`/"
        rlRun "cat /usr/share/doc/kernel-keys/`uname -r`/$cer_file | keyctl padd asymmetric kernelkey %:.ima"
        rlRun "keyctl show %:.ima | tee /tmp/.ima"
        rlAssertGrep "asymmetric: kernelkey" /tmp/.ima
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileSubmit /tmp/.builtin_trusted_keys
        rlFileSubmit /tmp/.ima
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
