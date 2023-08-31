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
        grubby --info=DEFAULT
        if stat /run/ostree-booted > /dev/null 2>&1; then
            CONFIG=/usr/lib/ostree-boot/config-$(uname -r)
        else
            CONFIG=/boot/config-$(uname -r)
        fi
        rlFileSubmit ${CONFIG}
    rlPhaseEnd

    rlPhaseStartTest
        if [[ $(uname -m) == "aarch64" ]] && $(rlIsRHEL 8); then
            echo "[SKIP] no integirty support for aarch64 on RHEL8"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            exit 0
        fi
        if [[ $(uname -m) == "ppc64le" || $(uname -m) == "aarch64" ]]; then
            rlAssertGrep 'CONFIG_HAVE_IMA_KEXEC=y' ${CONFIG}
            rlAssertGrep 'CONFIG_IMA_KEXEC=y' ${CONFIG}
        fi
        if [[ $(uname -m) == "ppc64le" || $(uname -m) == "x86_64" ]]; then
            rlAssertGrep 'CONFIG_IMA_ARCH_POLICY=y' ${CONFIG}
        fi
        if $(rlIsRHEL 9); then
            rlAssertGrep 'CONFIG_IMA_QUEUE_EARLY_BOOT_KEYS=y' ${CONFIG}
        fi
        rlAssertGrep 'CONFIG_IMA_APPRAISE_MODSIG=y' ${CONFIG}
        rlAssertGrep 'CONFIG_IMA_DEFAULT_HASH=\"sha256\"' ${CONFIG}
        rlAssertGrep 'CONFIG_IMA_DEFAULT_TEMPLATE=\"ima-sig\"' ${CONFIG}
        rlAssertGrep 'CONFIG_IMA_READ_POLICY=y' ${CONFIG}
        rlAssertGrep 'CONFIG_IMA_SIG_TEMPLATE=y' ${CONFIG}
        # bz2002350
        rlAssertGrep 'CONFIG_SYSTEM_BLACKLIST_KEYRING=y' ${CONFIG}
        rlAssertGrep '.blacklist' /proc/keys
        rlAssertGrep '.platform' /proc/keys
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
