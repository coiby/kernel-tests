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

TESTS=${TESTS:-}
GIT_URL=${GIT_URL:-"https://github.com/SUSE/qa_test_klp.git"}

function run_test()
{
    [ -z "$TESTS" ] && TESTS=$(ls klp_tc_*[0-9].sh)
IFS="
"
    for subtest in $TESTS; do
        sed -i '/set -e/d' $subtest
        rlPhaseStartTest $subtest
            rlWatchdog "./$subtest" 300 "15"
        rlPhaseEnd
    done
}


rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlRun "git clone ${GIT_URL}"
        rlRun "cd $(basename "${GIT_URL}")"
    rlPhaseEnd

    run_test

    rlPhaseStartCleanup
        for mod in $(lsmod | grep -E "^klp_" | awk '{ print $1; }'); do
            rlRun "rmmod -f $mod"
        done
        ps ax | tee ps_output.txt
        rstrnt-report-log -l ps_output.txt
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

