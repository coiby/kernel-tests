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
. ../../kernel-include/runtest.sh || exit 1
GIT_URL=${GIT_URL:-"https://gitlab.com/redhat/centos-stream/tests/ltp.git"}

rlJournalStart
    rlPhaseStartSetup
        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
        installer=$(K_GetPkgMgr)
        if [[ ${installer} == "rpm-ostree" ]]; then
            export install_opts="-A -y --idempotent --allow-inactive install"
        else
            export install_opts="-y install"
        fi
        ${installer} ${install_opts} ${devel_pkg}

        rlShowRunningKernel
        rlRun "git clone $GIT_URL" 0
        rlRun "cd ltp"
        rlRun "make -s autotools"
        rlRun "./configure > /dev/null"
        rlRun "make -s all &> /dev/null"
        rlRun "make -s install > /dev/null"
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "export KCONFIG_PATH=/usr/lib/ostree-boot/config-$(uname -r)"
            # for cve-2011-0999 and cve-2015-7550. Both needed extra time on ostree.
            rlRun "export LTP_TIMEOUT_MUL=3"
            # This is temporary until we can fix or figure out why this breaks ostree.
            rlRun "sed -i 's/cve-2018-1000204/#cve-2018-1000204/' /opt/ltp/runtest/cve"
        fi
    rlPhaseEnd

    rlPhaseStartTest "capability"
        rlRun "/opt/ltp/runltp -f capability"
    rlPhaseEnd

    rlPhaseStartTest "prot_hsymlinks"
        rlRun "/opt/ltp/runltp -f syscalls -s prot_hsymlinks"
    rlPhaseEnd

    rlPhaseStartTest "cve"
        rlRun "/opt/ltp/runltp -f cve"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make -s clean > /dev/null"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
