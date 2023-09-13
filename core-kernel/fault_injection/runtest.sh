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
. ../../kernel-include/runtest.sh || exit 1

# shellcheck disable=SC2206
fail_list=( ${fail_list:-failslab} )
OPTIONS=${OPTIONS:-"-p 100 -t 100 --interval=10 --verbose=2"}
GCMD=${GCMD:-""}

# shellcheck disable=SC2206
BASE_URL=( ${BASE_URL:-"https://cbs.centos.org/kojifiles/packages"} )
# shellcheck disable=SC2128 disable=SC2206
BEAKERLIB_rpm_fetch_base_url+=(${BASE_URL})

name=$(K_GetRunningKernelRpmName)
src_name=$(K_GetRunningKernelSrpmName)
version_release=$(K_GetRunningKernelRpmVersionRelease)
pkg="${name}"-"${version_release}"

function get_pkg_mgr()
{
    if [[ -e /run/ostree-booted ]]; then
      echo rpm-ostree
    elif [[ -e /usr/bin/dnf ]]; then
      echo dnf
    else
      echo yum
    fi
}

execute_fail()
{
    rlRun "sysctl vm.admin_reserve_kbytes=1048576"
    for fail in "${fail_list[@]}"; do
        rlRun "dmesg -C"
        case ${fail} in
            fail_make_request)
                # shellcheck disable=SC2154
                rlRun "partition=$(df | grep "/$" | awk '{print $1}' | awk -F "/" '{print $3}')"
                # shellcheck disable=SC2154
                rlRun "disk=${partition//[[:digit:]]/}"
                # shellcheck disable=SC2154
                rlRun "echo 1 > /sys/block/${disk}/${partition}/make-it-fail"
                CMD=${GCMD:-"touch fail_make_request.test"}
                ;;
            failslab)
                CMD=${GCMD:-"ls"}
                ;;
            fail_page_alloc)
                CMD=${GCMD:-"make -C tools/testing/selftests TARGETS=timens run_tests"}
                ;;
            fail_io_timeout)
                CMD=${GCMD:-"ls"}
                ;;
        esac
        rlRun "env FAILCMD_TYPE=${fail} bash ${FAILCMD} ${OPTIONS} -- ${CMD}" "0-127"
        rlRun "dmesg > '${fail}'.dmesg.log"
        rlAssertGrep "${fail}" "${fail}".dmesg.log -iq
        rlFileSubmit "${fail}".dmesg.log
    done
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if [[ ${name} =~ "debug" ]]; then
            # Get running kernel version of failcmd.sh.
            if (rlFetchSrcForInstalled "${pkg}"); then
                rlRun "rpm -ivh --define '_topdir ${PWD}' ${src_name}-${version_release}.src.rpm"
                pushd SPECS || exit 1
                rlRun "sed -i 's/efiuki 1/efiuki 0/' kernel.spec"
                rlRun "yum-builddep --downloadonly -y ./kernel.spec --downloaddir $(pwd)"
                pkg_mgr=$(get_pkg_mgr)
                if [[ $pkg_mgr == "rpm-ostree" ]]; then
                    echo "pkg_mgr = RPM OSTREE"
                    export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
                else
                    export pkg_mgr_inst_string="-y install"
                fi
                $pkg_mgr "$pkg_mgr_inst_string" ./*.rpm
                pushd ../SOURCES || exit 1
                rlRun "tar Jxf linux-${version_release}.tar.xz"
                pushd linux-"${version_release}"/ || exit 1
                FAILCMD=tools/testing/fault-injection/failcmd.sh
                rlRun "chmod 755 ${FAILCMD}"
            else
                rlLog "Could not get kernel src pkg. Provide a BASE_URL that contains the src package for your kernel version."
                rlPhaseEnd
                rlJournalEnd
                rlJournalPrintText
                exit 1
            fi
        else
            rlLog "This test can only be run on a debug kernel."
            rlPhaseEnd
            rlJournalEnd
            rlJournalPrintText
            exit 0
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "execute_fail"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm *.dmesg.log"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
