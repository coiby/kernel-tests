#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
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
if [ -z "${AUXILIARY_TYPES}" ]; then
    AUXILIARY_TYPES=(AT_HWCAP AT_HWCAP2 AT_PLATFORM)
else
    # shellcheck disable=SC2128
    mapfile -d ' ' -t AUXILIARY_TYPES < <(echo -n "${AUXILIARY_TYPES}")
fi
if [ -z "${AUXILIARY_VALUES}" ]; then
    AUXILIARY_VALUES=("${VAR_HWCAP}" "${VAR_HWCAP2}" "${VAR_PLATFORM}")
else
    # shellcheck disable=SC2128
    mapfile -d ' ' -t AUXILIARY_VALUES < <(echo -n "${AUXILIARY_VALUES}")
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest
        for key in "${!AUXILIARY_TYPES[@]}"; do
            vector=$(LD_SHOW_AUXV=1 sleep 0  | grep "${AUXILIARY_TYPES[${key}]}:" | awk '{print $2}')
            if [ -n "${vector}" ]; then
                if rlAssertEquals "Checking value for ${AUXILIARY_TYPES[${key}]}" "${vector}"  "${AUXILIARY_VALUES[${key}]}"; then
                    echo "PASS: ${AUXILIARY_TYPES[${key}]}" >> auxvec.log
                else
                    echo "FAIL: ${AUXILIARY_TYPES[${key}]}" >> auxvec.log
                fi
            else
                rlLog "UNSUPPORTED: ${AUXILIARY_TYPES[${key}]}, check spelling."
                echo "UNSUPPORTED: ${AUXILIARY_TYPES[${key}]}" >> auxvec.log
            fi
        done
        rlFileSubmit auxvec.log
        rlRun "cat auxvec.log"
    rlPhaseEnd
    rlPhaseStartCleanup
        rm auxvec.log
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
