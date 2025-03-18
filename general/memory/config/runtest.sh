#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
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
. /usr/share/beakerlib/beakerlib.sh || exit 2
. ./lib/lib.sh
. ../../../kernel-include/runtest.sh || exit 2


trap 'rlFileRestore; exit' SIGHUP SIGINT SIGQUIT SIGTERM

export DIR_CASE=$PWD/testcase
export DIR_SOURCE=$DIR_CASE/source
export DIR_BIN=$DIR_ENTRY/debug/bin


CASELIST=${CASELIST:-*}

declare -A KNOWN_ISSUE_LIST
declare -A KNOWN_FILED_BUGS
# Test admin_reserve_kbytes.sh reported bz1908668
KNOWN_ISSUE_LIST["rhel"]="admin_reserve_kbytes:bz1908668"
# To mean bz1908668 exists in several kernel version ranges,'*' repsents infinite value.
# KNOWN_FILED_BUGS["bz1908668"]="A->B C->D E->*"
KNOWN_FILED_BUGS["bz1908668"]="4.18.0-220.el8->*"

function install_kernel_devel()
{
    rlShowRunningKernel
    devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
    pkg_mgr=$(K_GetPkgMgr)
    rlLog "pkg_mgr = ${pkg_mgr}"
    if [[ $pkg_mgr == "rpm-ostree" ]]; then
        export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
    else
        export pkg_mgr_inst_string="-y install"
    fi
    # shellcheck disable=SC2086
    ${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg}
}

function run_cases()
{
    local subcase
    local subfunc
    local pathname
    local casespath
    local pname
    local ptype

    for subcase in $CASELIST; do
        casespath+="$(find $DIR_CASE -name "${subcase}.sh" | sort) "
    done

    for subcase in $casespath; do
        pathname=$(dirname $subcase)
        subfunc=$(basename ${subcase%.sh})
        pname=$subfunc
        ptype=FAIL
        # shellcheck disable=SC1090
        source $subcase

        check_knownissues $subfunc

        rlPhaseStart $ptype "`basename $pathname` $pname"
        rlWatchdog "eval $subfunc" 3600 "9"
        unset -f $subfunc
        rlPhaseEnd

        [ ! -f $DIR_DEBUG/DEBUG ] && mv $subcase ${subcase}.done
        [ -f $DIR_DEBUG/REBOOTAFTERDONE ] && rm -vf $DIR_DEBUG/REBOOTAFTERDONE && rstrnt-reboot && sleep 10000
    done
}

function prep_tst_info()
{
    local subcase
    local pathname
    local cfg_name
    local cfg_type
    local casespath
    local iter=1

    touch tst_config_list
    if test -s tst_config_list; then
        return
    fi
    for subcase in $CASELIST; do
        casespath+="$(find $DIR_CASE -name "${subcase}.sh" | sort) "
    done
    rlLogInfo "configs to test:"
    for subcase in $casespath; do
        pathname=$(dirname $subcase)
        # cmdline or proc_sysctl
        cfg_type=$(basename $pathname)
        cfg_name=$(basename ${subcase%.sh})
        echo ${cfg_type}:${cfg_name} >> tst_config_list
        rlLogInfo "** ($((iter++))) ${cfg_type}:${cfg_name} **"
    done
    rlFileSubmit tst_config_list
}

rlJournalStart
    rlPhaseStartSetup
        [ ! -d $DIR_BIN ] && rlRun "mkdir -p $DIR_BIN"
        install_kernel_devel
        prep_tst_info
        rlRun "TmpDir=\$(mktemp -d -p $DIR_ENTRY)" 0 "Creating tmp directory"
        # shellcheck disable=SC2154
        rlRun "pushd $TmpDir"
    rlPhaseEnd

    run_cases

    rlPhaseStartCleanup
        rlRun "popd"
        rlLogInfo "$(get_skip_summary)"
        [ ! -f $DIR_DEBUG/DEBUG ] && rlRun "rm -r $TmpDir" 0-254 "Removing tmp directory"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
