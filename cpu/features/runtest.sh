#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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

# default features are for aarch64.
if [ -z "${FEATURES}" ]; then
    FEATURES=(aarch64.cpu_features.bti aarch64.cpu_features.midr_el1 aarch64.cpu_features.mte_state aarch64.cpu_features.sve aarch64.cpu_features.zva_size aarch64.processor\\[0x0\\].midr_el1 aarch64.processor\\[0x0\\].dczid_el0)
else
    # shellcheck disable=SC2128
    mapfile -d ' ' -t FEATURES < <(echo -n "${FEATURES}")
fi
if [ -z "${VALUES}" ]; then
    VALUES=("${VAR_BTI}" "${VAR_MIDR_EL1}" "${VAR_MTE_STATE}" "${VAR_SVE}" "${VAR_ZVA_SIZE}" "${VAR_MIDR_EL1_0}" "${VAR_DCZID_EL0_0}")
else
    # shellcheck disable=SC2128
    mapfile -d ' ' -t VALUES < <(echo -n "${VALUES}")
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlRun "cpu_count=$(lscpu | grep "^CPU(s):" | awk '{print $2}')"
    rlPhaseEnd
    rlPhaseStartTest "Check cpu features and processor values."
        for key in "${!FEATURES[@]}"; do
            value=$(ld.so --list-diagnostics | grep "${FEATURES[${key}]}" | awk -F = '{print $2}')
            if [ -n "${value}" ]; then
                if rlAssertEquals "Checking value for ${FEATURES[${key}]}" "${value}"  "${VALUES[${key}]}"; then
                    echo "PASS: ${FEATURES[${key}]}" >> cpu_features.log
                else
                    echo "FAIL: ${FEATURES[${key}]}" >> cpu_features.log
                fi
            else
                rlFail "UNSUPPORTED: ${FEATURES[${key}]}, check spelling."
                echo "UNSUPPORTED: ${FEATURES[${key}]}" >> cpu_features.log
            fi
            if [[ "${FEATURES[${key}]}" =~ aarch64.processor ]]; then
                i=0
                # shellcheck disable=SC2154
                while ((i++ < $(($cpu_count-1))));
                do
                    processor=$(echo "${FEATURES[${key}]}" | sed -e "s/0x0/0x$i/")
                    value=$(ld.so --list-diagnostics | grep "${processor}" | awk -F = '{print $2}')
                    if [ -n "${value}" ]; then
                        if rlAssertEquals "Checking value for ${processor}" "${value}"  "${VALUES[${key}]}"; then
                            echo "PASS: ${processor}" >> cpu_features.log
                        else
                            echo "FAIL: ${processor}" >> cpu_features.log
                        fi
                    else
                        rlFail "UNSUPPORTED: ${processor}, check spelling."
                        echo "UNSUPPORTED: ${processor}" >> cpu_features.log
                    fi
                done
            fi
        done
        rlFileSubmit cpu_features.log
        rlRun "cat cpu_features.log"
    rlPhaseEnd
    rlPhaseStartCleanup
        rm cpu_features.log
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
