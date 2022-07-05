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
        grep CONFIG_IMA /boot/config-`uname -r`
        rlRun "yum install -y grubby"
    rlPhaseEnd

    rlPhaseStartTest
        grubby --info=DEFAULT
        if [ ! -f ./REBOOT ]; then
            grubby --args="ima_appraise=fix" --update-kernel=DEFAULT
            grubby --args="ima_policy=appraise_tcb" --update-kernel=DEFAULT
            [[ $(uname -i) == "s390x" ]] && zipl
            touch ./REBOOT
            rhts-reboot
        else
            rm -f ./REBOOT
            rlRun "cat /proc/cmdline | tee proc_cmdline.txt"
            rlFileSubmit proc_cmdline.txt
            rlRun "grep 'ima_appraise=fix' proc_cmdline.txt"
            rlRun "grep 'ima_policy=appraise_tcb' proc_cmdline.txt"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rm -f ./REBOOT
        grubby --remove-args="ima_appraise=fix" --update-kernel=DEFAULT
        grubby --remove-args="ima_policy=appraise_tcb" --update-kernel=DEFAULT
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
