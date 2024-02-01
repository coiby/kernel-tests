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
GIT_URL=${GIT_URL:-"https://gitlab.com/redhat/centos-stream/tests/ltp.git"}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "export KCONFIG_PATH=/usr/lib/ostree-boot/config-$(uname -r)"
        fi
        rlRun "git clone $GIT_URL" 0
        rlRun "cd ltp"
        rlRun "make -s autotools"
        rlRun "./configure"
        rlRun "make &> /dev/null"
        rlRun "make -s install"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "/opt/ltp/runltp -f syscalls -s key"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make -s clean"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
