#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/OpenIPMI/Regression/bz311231-ipmitool-does-not-check-input-values
#   Description: Test for bz311231 ([RHEL5]ipmitool configuration does not check input)
#   Author: Karel Volny <kvolny@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2009 Red Hat, Inc. All rights reserved.
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

# Include rhts environment
. /usr/bin/rhts-environment.sh
# shellcheck disable=SC1091
. /usr/share/rhts-library/rhtslib.sh

# shellcheck disable=SC2034
PACKAGE="OpenIPMI"

# SOL_COMMAND = sol command to test
# UGLY_VALUES = values that the command should not accept
# GOOD_VALUES = values that the command should accept
SOL_COMMAND[1]="set-in-progress"
UGLY_VALUES[1]="asdf 0 true set-completeset-in-progresscommit-write"
GOOD_VALUES[1]="set-complete set-in-progress commit-write"
SOL_COMMAND[2]="enabled"
UGLY_VALUES[2]="asdf 0 1 truefalse falsetrue"
GOOD_VALUES[2]="true false"
SOL_COMMAND[3]="force-encryption"
UGLY_VALUES[3]="asdf 0 1 truefalse falsetrue"
GOOD_VALUES[3]="true false"
SOL_COMMAND[4]="force-authentication"
UGLY_VALUES[4]="asdf 0 1 truefalse falsetrue"
GOOD_VALUES[4]="true false"
SOL_COMMAND[5]="privilege-level"
UGLY_VALUES[5]="asdf 0 true useroperatoradminoem"
GOOD_VALUES[5]="user operator admin oem"
SOL_COMMAND[6]="character-accumulate-level"
UGLY_VALUES[6]="0 true 256 257 65537"
GOOD_VALUES[6]="1 127 255"
SOL_COMMAND[7]="character-send-threshold"
UGLY_VALUES[7]="asdf true 256 257 16777216"
GOOD_VALUES[7]="0 128 255"
SOL_COMMAND[8]="retry-count"
UGLY_VALUES[8]="true 8 256 65537"
GOOD_VALUES[8]="0 3 7"
SOL_COMMAND[9]="retry-interval"
UGLY_VALUES[9]="asdf true 256 65537 16777216"
GOOD_VALUES[9]="0 100 255"
SOL_COMMAND[10]="non-volatile-bit-rate"
UGLY_VALUES[10]="parallel true 96 19."
GOOD_VALUES[10]="serial 9.6 19.2 38.4 57.6 115.2"
SOL_COMMAND[11]="volatile-bit-rate"
UGLY_VALUES[11]="parallel false 1152 .6"
GOOD_VALUES[11]="serial 9.6 19.2 38.4 57.6 115.2"

PAYLOAD_COMMAND[1]="status"
PAYLOAD_VALUES[1]="abcd 1000 2x1"
PAYLOAD_COMMAND[2]="enable"
PAYLOAD_VALUES[2]="abcd 1000 2x1"
PAYLOAD_COMMAND[3]="disable"
PAYLOAD_VALUES[3]="abcd 1000 2x1"

rlJournalStart
    rlPhaseStartSetup
        rlRun "TmpDir=\`mktemp -d\`" 0 "Creating tmp directory"
        # shellcheck disable=SC2154
        rlRun "pushd $TmpDir"
        # stop the service to make sure /dev/ipmi0 does not exist and we get expected error messages
        rlServiceStop ipmi
    rlPhaseEnd

    for index in $(seq 11); do
        rlPhaseStartTest "ipmitool sol set ${SOL_COMMAND[index]}"
            # check that all bad values report "Invalid value ..."
            for value in ${UGLY_VALUES[index]}; do
                rlRun "ipmitool sol set ${SOL_COMMAND[index]} $value &> ${index}-${value}.out" 1
                rlAssertGrep "Invalid value" "${index}-${value}.out"
                # DEBUG
                    echo "${SOL_COMMAND[index]} ${value} output:"
                    cat "${index}-${value}.out"
            done
            # check that impitool tries to pass all valid values ...
            for value in ${GOOD_VALUES[index]}; do
                rlRun "ipmitool sol set ${SOL_COMMAND[index]} $value &> ${index}-${value}.out" 1
                # ^ note that non-zero exitcode is expected, as impi is not running
                # and thus opening the device fails:
                rlAssertGrep "Could not open device" "${index}-${value}.out"
                # DEBUG
                    echo "${SOL_COMMAND[index]} ${value} output:"
                    cat "${index}-${value}.out"
            done
        rlPhaseEnd
    done

    for index in $(seq 2); do
        rlPhaseStartTest "ipmitool sol payload ${PAYLOAD_COMMAND[index]}"
            # check that all bad values report "Invalid ..."
            for value in ${PAYLOAD_VALUES[index]}; do
                rlRun "ipmitool sol payload ${PAYLOAD_COMMAND[index]} $value &> ${index}-${value}.out" 1
                rlAssertGrep "Invalid channel" "${index}-${value}.out"
                # DEBUG
                    echo "${SOL_COMMAND[index]} ${value} output:"
                    cat "${index}-${value}.out"
            done
            for value in ${PAYLOAD_VALUES[index]}; do
                rlRun "ipmitool sol payload ${PAYLOAD_COMMAND[index]} 0 $value &> ${index}-0-${value}.out" 1
                rlAssertGrep "Invalid user" "${index}-0-${value}.out"
                # DEBUG
                    echo "${SOL_COMMAND[index]} 0 ${value} output:"
                    cat "${index}-0-${value}.out"
            done
        rlPhaseEnd
    done

    rlPhaseStartCleanup
        rlServiceRestore ipmi
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
