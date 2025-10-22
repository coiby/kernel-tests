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
. ../../../kernel-include/runtest.sh || exit 1
GIT_URL=${GIT_URL:-"https://gitlab.com/redhat/centos-stream/tests/kernel/core/ltp.git"}
LTP_TAG=${LTP_TAG:-""}

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

        if [ "${RSTRNT_REBOOTCOUNT}" -ge 1 ]; then
            echo "===== Test has already been run,
            Check logs for possible failures ======"
            rstrnt-report-result CHECKLOGS FAIL 99
            exit 0
        fi

        if [ -z "$LTP_TAG" ]; then
            LTP_TAG="master"

            # using distribution/ltp as reference
            if rlIsRHEL '6'; then
                LTP_TAG="20200120"
            elif rlIsRHEL '7'; then
                LTP_TAG="20210927"
            elif rlIsRHEL '8.2'; then
                LTP_TAG="20230929"
            elif rlIsRHEL '>=8.4' && rlIsRHEL '<9.5'; then
                LTP_TAG="20240129"
            elif rlIsRHEL '>=9.5' && rlIsRHEL '<9.6'; then
                LTP_TAG="20250530"
            fi
        fi

        rlShowRunningKernel
        rlLog "LTP version: $LTP_TAG"
        rlRun "git clone $GIT_URL --branch $LTP_TAG --depth=1" 0
        rlRun "cd ltp"
        if rlIsRHEL '>9' && [[ $(uname -m) == "x86_64" ]]; then
            rlRun "sed -i '/cve-2015-3290:*\+/ s/$/ -O0/' testcases/cve/Makefile"
        fi
        rlRun "make -s autotools"
        rlRun "./configure > /dev/null"
        rlRun "export LTP_TIMEOUT_MUL=2"
    rlPhaseEnd

    rlPhaseStartTest "crypto $TEST"
        if [ -z "$TEST" ]; then
            rlRun "make -s all &> /dev/null"
            rlRun "make -s install > /dev/null"
            rlRun "/opt/ltp/runltp -f crypto"
        else
            rlRun "cd testcases/kernel/crypto/"
            rlRun "make -s $TEST"
            rlRun "./$TEST"
        fi
        rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make -s clean > /dev/null"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
