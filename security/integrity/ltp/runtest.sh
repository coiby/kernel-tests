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
GIT_URL=${GIT_URL:-"https://github.com/linux-test-project/ltp.git"}

rlJournalStart
    rlPhaseStartSetup
        grubby --info=DEFAULT
        if [ ! -f ./REBOOT ]; then
            grubby --args="ima_tcb" --update-kernel=DEFAULT
            grubby --args="ima_appraise=fix" --update-kernel=DEFAULT
            [[ $(uname -m) == "s390x" ]] && zipl
            touch ./REBOOT
            rhts-reboot
        else
            rlRun "cat /proc/cmdline | tee proc_cmdline.txt"
            rlFileSubmit proc_cmdline.txt
            rlRun "grep 'ima_tcb' proc_cmdline.txt"
            rlRun "grep 'ima_appraise=fix' proc_cmdline.txt"
        fi
        rm -f ./REBOOT
        rlShowRunningKernel
        rlRun "git clone $GIT_URL" 0
        rlRun "cd ltp"
        rlRun "make -s autotools"
        rlRun "./configure > /dev/null"
        rlRun "make -s all &> /dev/null"
        rlRun "make -s install > /dev/null"
    rlPhaseEnd

    rlPhaseStartTest
        unset $TEST_FILE
        rlRun "id"
        rlRun "cat /proc/self/loginuid"
        rlRun "echo $(id -u) > /proc/self/loginuid"
        rlRun "/opt/ltp/runltp -f ima"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make -s clean > /dev/null"
        rm -f ./REBOOT
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
