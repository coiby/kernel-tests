#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/crypto/2174928
#   Description: Test for BZ#2174928 (Note: test will enable FIPS mode, and should be append to the last test to execute if combinding with other tests)
#   Author: Dennis Li <denli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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
threshold=25
TmpDir=./tmp

rlJournalStart
    if ! [[ -e /tmp/enable_fips_attempted ]]; then
        rlPhaseStartSetup
            rlShowRunningKernel
            grubby --info=DEFAULT
            rlRun "mkdir $TmpDir" 0 "Creating tmp directory"
            rlRun "cp threaded_getrandom.c threaded_getrandom_ns.c $TmpDir"
            rlRun "pushd $TmpDir"
            rlRun "touch before_fips.log"
            rlRun "touch after_fips.log"
            if [[ $(uname -m) = "x86_64" ]]; then
                rlRun "gcc -pthread -o threaded_getrandom threaded_getrandom.c"
            else
                rlRun "gcc -pthread -o threaded_getrandom threaded_getrandom_ns.c"
            fi
            rlRun "fips-mode-setup --is-enabled" 2 && rlDie "FIPS mode is enabled before test setup, please start test without FIPS mode"
        rlPhaseEnd

        rlPhaseStartTest "iteration 1000 and 10000 before enable FIPS mode"
            rlRun -l "./threaded_getrandom 1000 2> ./before_fips.log" 0
            rlRun -l "./threaded_getrandom 10000 2>> ./before_fips.log" 0
        rlPhaseEnd
    elif [[ -e /tmp/disable_fips_attempted ]]; then
        rlPhaseStartCleanup
            rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        [[ -e /tmp/enable_fips_attempted ]] && rlRun "rm /tmp/enable_fips_attempted"
        [[ -e /tmp/disable_fips_attempted ]] && rlRun "rm /tmp/disable_fips_attempted"
            rlRun "fips-mode-setup --is-enabled" 1 && fips_enabled=1
            if [ ${fips_enabled} ]; then
                rlDie "Failed to disable FIPS, remaining testsuite might be effected"
            else
                rlLog "FIPS mode disabled, end of test" && exit 0
            fi
        rlPhaseEnd

    else
        rlRun "pushd $TmpDir"
    fi

    rlPhaseStartTest "enabling FIPS mode and check"
        rlRun "fips-mode-setup --check"
        fips-mode-setup --is-enabled && rlPass "FIPS mode is enabled" && fips_enabled=1
        if [ ! ${fips_enabled} ]; then
            [[ -e /tmp/enable_fips_attempted ]] && rlDie "Failed to enable FIPS, end of test"
            touch /tmp/enable_fips_attempted && sync
            if stat /run/ostree-booted > /dev/null 2>&1; then
                rlRun -l "fips-mode-setup --enable --no-bootcfg"
                kernel_args=$(fips-mode-setup --enable --no-bootcfg | awk -F\" '/fips=1/ {print $2}')
                kernel_current=$(grubby --info=DEFAULT | awk -F\" '/kernel=/ {print $2}')
                grubby --update-kernel="${kernel_current}" --args="${kernel_args}"
            else
                rlRun -l "fips-mode-setup --enable"
            fi
            rlRun "rhts-reboot"
        fi
    rlPhaseEnd

    rlPhaseStartTest "iteration 1000 and 10000 after enable FIPS mode"
        rlRun -l "./threaded_getrandom 1000 2> ./after_fips.log" 0
        rlRun -l "./threaded_getrandom 10000 2>> ./after_fips.log" 0
    rlPhaseEnd

    rlPhaseStartTest "Asserting FIPS mode getrandom() function time ratio less than threshold"
        before_fips_avg=$((($(cut -d',' -f1 before_fips.log) + $(cut -d',' -f2 before_fips.log))/2))
        after_fips_avg=$((($(cut -d',' -f1 after_fips.log) + $(cut -d',' -f2 after_fips.log))/2))
        ((avg_diff=after_fips_avg/before_fips_avg))
        rlAssertLesser "Average difference:$avg_diff should be smaller than Threshold:$threshold" $avg_diff $threshold
    rlPhaseEnd

    rlPhaseStartTest "Disabling FIPS mode."
        rlRun -l "fips-mode-setup --disable"
        touch /tmp/disable_fips_attempted && sync
        rlRun "rhts-reboot"
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
