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

# shellcheck disable=SC2206
BASE_URL=( ${BASE_URL:-"https://cbs.centos.org/kojifiles/packages"} )
baseline=${baseline:-""}

name=$(rpm --queryformat '%{name}\n' -qf /boot/config-"$(uname -r)" | sed -e "s/-core//g" -e "s/-debug//g")
version=$(uname -r | cut -f1 -d'-')
test_release=$(uname -r | cut -f2 -d'-' | sed "s/\.$(arch).*//")

fetch_src()
{
    release=${1}
    scratch=${2}
    pkg=${name}-${version}-${release}
    found=0
    for URL in "${BASE_URL[@]}"; do
        if [ -z "${scratch}" ]; then
            rlRun "wget ${URL}/${name}/${version}/${release}/src/${pkg}.src.rpm && found=1" "0-127"
        else
            rlRun "wget ${URL}/${pkg}.src.rpm && found=1" "0-127"
        fi
        [[ ${found} -eq 0 ]] || break
    done
    rlAssertEquals "Checking if rpm found..." ${found} 1 || exit 1
    rlRun "mkdir ${pkg}"
    rlRun "rpm -ivh --define '_topdir ${PWD}/${pkg}' ${name}-${version}-${release}.src.rpm"
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if [ -z "${baseline}" ]; then
            rlFail "baseline not set. Please set baseline env variable and retry."
            rlLog "Examples:"
            rlLog "    rhivos: 354.317.el9iv"
            rlLog "    rhel: 354.el9"
            rlPhaseEnd
            rlJournalEnd
            exit 1
        fi
        rlRun "fetch_src ${baseline}"
        if [ -z "${scratch_build}" ]; then
            rlRun "fetch_src ${test_release}"
        else
            rlRun "fetch_src ${test_release} 1"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "diff ${name}-${version}-${baseline}/SOURCES/${name}-$(arch)-rhel.config ${name}-${version}-${test_release}/SOURCES/${name}-$(arch)-rhel.config | tee diff_config_${baseline}_to_${test_release}.log"
        rlFileSubmit diff_config_"${baseline}"_to_"${test_release}".log
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -rf ${name}-${version}-${baseline} ${name}-${version}-${test_release}"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
