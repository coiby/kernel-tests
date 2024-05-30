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
. ../../../cmdline_helper/libcmd.sh || exit 1
. ../../../cki_lib/libcki.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if stat /run/ostree-booted > /dev/null 2>&1; then
            grep CONFIG_IMA /usr/lib/ostree-boot/config-`uname -r`
        else
            grep CONFIG_IMA /boot/config-`uname -r`
        fi
    rlPhaseEnd

    rlPhaseStartTest
        grubby --info=DEFAULT
        if [ ! ${RSTRNT_REBOOTCOUNT} -gt 0 ]; then
            if cki_is_abd; then
                rlRun "add_aboot_param ima_policy=tcb"
                rlRun "add_aboot_param ima_template_fmt=d"
            elif stat /run/ostree-booted > /dev/null 2>&1; then
                rpm-ostree kargs --append-if-missing=ima_policy=tcb --append-if-missing=ima_template_fmt=d --import-proc-cmdline
            else
                grubby --args="ima_policy=tcb" --update-kernel=DEFAULT
                grubby --args="ima_template_fmt=d" --update-kernel=DEFAULT
            fi
            [[ $(uname -m) == "s390x" ]] && zipl
            rstrnt-reboot
        elif [ ${RSTRNT_REBOOTCOUNT} -eq 1 ]; then
            rlRun "cat /proc/cmdline | tee proc_cmdline.txt"
            rlFileSubmit proc_cmdline.txt
            rlRun "grep 'ima_policy=tcb' proc_cmdline.txt"
            rlRun "grep 'ima_template_fmt=d' proc_cmdline.txt"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        if [ ! ${RSTRNT_REBOOTCOUNT} -gt 1 ]; then
        if cki_is_abd; then
                rlRun "remove_aboot_param ima_policy=tcb"
                rlRun "remove_aboot_param ima_template_fmt=d"
            elif stat /run/ostree-booted > /dev/null 2>&1; then
                rpm-ostree kargs --delete-if-present=ima_policy=tcb --delete-if-present=ima_template_fmt=d --import-proc-cmdline
            else
                grubby --remove-args="ima_policy=tcb" --update-kernel=DEFAULT
                grubby --remove-args="ima_template_fmt=d" --update-kernel=DEFAULT
            fi
            [[ $(uname -m) == "s390x" ]] && zipl
            rstrnt-reboot
        fi
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
