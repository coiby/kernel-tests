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
GIT_URL=${GIT_URL:-"https://gitlab.com/redhat/centos-stream/tests/kernel/audit-testsuite"}
GIT_REF=${GIT_REF:-"main"}

report_subtests() {
    local subtest=""
    local results_log=$1

    subtest_regex="[a-zA-Z0-9_]+/test[[:space:]]*\.+[[:space:]]*"
    while IFS= read -r line; do
        if [[ "$line" =~ ${subtest_regex} ]]; then
            subtest="$(echo $line | sed 's/^[[:space:]]*//;s/test.*/test/')"
            if [[ "$line" =~ ok ]]; then
                rlReport "$subtest" PASS 0 results.log
                rlPass "$subtest"
            elif [[ "$line" =~ Failed ]]; then
                rlReport "$subtest" FAIL 1 results.log
                rlFail "$subtest"
            fi
        fi
    done < "$results_log"
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlIsRHEL "<9" && { yum install -y perl-tests; }
        [ "$(uname -m)" = "x86_64" ] && { yum install -y glibc.i686 glibc-devel.i686 libgcc.i686; }
        rlIsRHEL ">9" && { yum install -y kernel-modules-extra; }
        rlRun "perl -MCPAN -e 'install Socket::Netlink' > perlCPAN.log 2>&1"
        rlFileSubmit perlCPAN.log
        rlRun "git clone $GIT_URL"
        rlRun "pushd audit-testsuite"
        rlRun "git checkout $GIT_REF"
        rlIsRHEL "<9" && rlRun "sed -i '/backlog_wait_time_actual_reset/d' tests/Makefile"
        rlIsRHEL ">9" && rlRun "sed -i '/syscall_socketcall/d' tests/Makefile"
        rlRun "sysctl kernel.io_uring_disabled | grep -q 'kernel.io_uring_disabled = 0'" 0-1 || rlRun "sed -i '/io_uring/d' tests/Makefile"
    rlPhaseEnd

    rlPhaseStartTest "Audit testsuite"
        rlRun "unset DISTRO"
        rlRun "cat /proc/self/loginuid && echo $(id -u) > /proc/self/loginuid" 0-255
        rlRun "unbuffer make test |& tee results.log" 0-255
        report_subtests results.log
        rlLog "See test detail in results.log"
        rlFileSubmit results.log
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make clean"
        rlRun "popd"
        rlRun "rm -rf audit-testsuite"
        rlRun "rm -f perlCPAN.log"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
