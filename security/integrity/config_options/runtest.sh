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
        rlFileSubmit /boot/config-$(uname -r)
    rlPhaseEnd

    rlPhaseStartTest
        if [[ $(uname -i) == "aarch64" ]] && $(rlIsRHEL 8); then
            echo "[SKIP] no integirty support for aarch64 on RHEL8"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            exit 0
        fi
        if [[ $(uname -i) == "ppc64le" || $(uname -i) == "aarch64" ]]; then
            rlAssertGrep 'CONFIG_HAVE_IMA_KEXEC=y' /boot/config-$(uname -r)
            rlAssertGrep 'CONFIG_IMA_KEXEC=y' /boot/config-$(uname -r)
        fi
        if [[ $(uname -i) == "ppc64le" || $(uname -i) == "x86_64" ]]; then
            rlAssertGrep 'CONFIG_IMA_ARCH_POLICY=y' /boot/config-$(uname -r)
        fi
        if $(rlIsRHEL 9); then
            rlAssertGrep 'CONFIG_IMA_QUEUE_EARLY_BOOT_KEYS=y' /boot/config-$(uname -r)
        fi
        rlAssertGrep 'CONFIG_IMA_APPRAISE_MODSIG=y' /boot/config-$(uname -r)
        rlAssertGrep 'CONFIG_IMA_DEFAULT_HASH=\"sha256\"' /boot/config-$(uname -r)
        rlAssertGrep 'CONFIG_IMA_DEFAULT_TEMPLATE=\"ima-sig\"' /boot/config-$(uname -r)
        rlAssertGrep 'CONFIG_IMA_READ_POLICY=y' /boot/config-$(uname -r)
        rlAssertGrep 'CONFIG_IMA_SIG_TEMPLATE=y' /boot/config-$(uname -r)
        # bz2002350
        rlAssertGrep 'CONFIG_SYSTEM_BLACKLIST_KEYRING=y' /boot/config-$(uname -r)
        rlAssertGrep '.blacklist' /proc/keys
        rlAssertGrep '.platform' /proc/keys
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
