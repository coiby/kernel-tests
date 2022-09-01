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
        rlIsRHEL "<9.1" && { echo "only applies to RHEL 9.1 or newer"; rstrnt-report-result $RSTRNT_TASKNAME SKIP; exit 0; }
        grubby --info=DEFAULT
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlFileSubmit /usr/lib/ostree-boot/config-$(uname -r)
            grep 'CONFIG_INTEGRITY=y' /usr/lib/ostree-boot/config-$(uname -r) || { echo "integrity subsystem disabled"; rstrnt-report-result $RSTRNT_TASKNAME SKIP; exit 0; }
        else
            rlFileSubmit /boot/config-$(uname -r)
            grep 'CONFIG_INTEGRITY=y' /boot/config-$(uname -r) || { echo "integrity subsystem disabled"; rstrnt-report-result $RSTRNT_TASKNAME SKIP; exit 0; }
        fi

    rlPhaseEnd

    rlPhaseStartTest
    rlRun "evmctl ima_hash -a sha256 runtest.sh"
    rlRun "evmctl ima_hash -a sha384 runtest.sh"
    rlRun "evmctl ima_hash -a sha512 runtest.sh"
    rlRun "echo 'appraise func=SETXATTR_CHECK appraise_algos=sha512,sha384' > /sys/kernel/security/integrity/ima/policy"
    rlRun "dmesg | tail -1 | grep 'policy update completed'"
    rlRun "evmctl ima_hash -a sha384 runtest.sh"
    rlRun "evmctl ima_hash -a sha512 runtest.sh"
    rlRun "getfattr -d -m - runtest.sh"
    rlRun "evmctl ima_hash -a sha256 runtest.sh" 1-255
    rlRun "ausearch --input-logs -c evmctl"
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
