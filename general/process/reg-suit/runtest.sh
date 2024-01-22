#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of memory regression test-suit
#   Description: TestCaseComment
#   Author: Chunyu Hu <chuhu@redhat.com>
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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ./lib/lib.sh

trap 'rlFileRestore; exit' SIGHUP SIGINT SIGQUIT SIGTERM

export CPUCOUNT=$(grep -c -w  processor /proc/cpuinfo)
export DIR_CASE=$PWD/testcase
export DIR_SOURCE=$DIR_CASE/source
export DIR_MODULE=$DIR_CASE/module
export DIR_DONE=$PWD/testDone
export DIR_BIN=$DIR_ENTRY/debug/bin


BZLIST=${BZLIST:-}
SKIPLIST=${SKIPLIST:-}
DEBUG_MODE=${DEBUG_MODE:-0}

declare -A KNOWN_ISSUE_LIST
declare -A KNOWN_FILED_BUGS

# It means sub test bzdeadline.sh reported bz1868611,format I.
KNOWN_ISSUE_LIST["rhel8"]="bzdeadline:bz1868611"
# It means sub test bzdeadline.sh reported bz1868611,format II.
KNOWN_FILED_BUGS["bzdeadline"]="bz1868611"

function run_regression()
{
    local subcase
    local subfunc
    local findargs
    local ptype=FAIL
    local pname
    findargs=$(echo $BZLIST | awk -v RS=' ' -v ORS=' ' '{print "-o -name bz*"$1".sh"}')
    # shellcheck disable=SC2044
    for subcase in $(find $DIR_CASE -maxdepth 1 -name notexist $findargs); do
        # shellcheck disable=SC1090
        . $subcase
        # Since 'basename -s' is not supported on rhel6, remove suffix '.sh' with bash parameter expansion.
        #subfunc=$(basename -s .sh $subcase)
        subfunc=$(basename ${subcase%.sh})
        pname=$subfunc
        ptype=FAIL
        echo ${subfunc#bz} > $REBOOT_DOGFILE; sync; sleep 1

        # If bzdeadline.sh reported bug bz1868611, the result will be like:
        # rlReport bzdeadline_bz1868611 WARN
        if echo ${KNOWN_ISSUE_LIST[$RELEASE]} | grep -q $subfunc; then
            ptype=WARN
            pname=${subfunc}_$(echo ${KNOWN_ISSUE_LIST[$RELEASE]} | awk -F: -v RS=' ' '/'$subfunc'/ {if (NF>1) {gsub(",","_",$2);printf("%s",$2)} else {printf("%s", $1)} exit 0}')
        elif echo ${!KNOWN_FILED_BUGS[*]} | grep -q $subfunc; then
            ptype=WARN
            pname=${subfunc}_${KNOWN_FILED_BUGS[$subfunc]// /_}
        fi

        rlPhaseStart $ptype $pname
        if ((DEBUG_MODE)); then
            echo "Before running $subfunc"
            echo
            pstree -nalp $(ps -C restraintd --no-headers -o pid | awk '{gsub(" ","");print}')
        fi

        rlWatchdog "eval $subfunc" 3600 "9"

        if ((DEBUG_MODE)); then
            echo "After running $subfunc"
            echo
            pstree -nalp $(ps -C restraintd --no-headers -o pid | awk '{gsub(" ","");print}')
        fi

        unset -f $subfunc
        rlPhaseEnd
        [ ! -f $DIR_DEBUG/DEBUG ] && mv $subcase $DIR_DONE/
    done
}

function init_skip()
{
    local subcase
    local lastpanic=$(cat $REBOOT_DOGFILE)
    for subcase in ${SKIPLIST} ${lastpanic}; do
        if [ ! -f "${DIR_CASE}/bz${subcase}.sh" ]; then
            continue;
        fi
        rlPhaseStartTest "bz${subcase}_skipped"
        mark_skip "bz${subcase}" "skipped as global SKIPLIST env."
        rlPhaseEnd
        mv "${DIR_CASE}/bz${subcase}.sh" $DIR_DONE/
    done
}

rlJournalStart
    rlPhaseStartSetup
        echo "Init Meminfo:"
        cat /proc/meminfo
        echo "Init hugepage meminfo:"
        find /sys/devices/system/node -name nr_hugepages -exec cat {} \; -a -printf "%h/%f\n"
        [ ! -d $DIR_DONE ] && rlRun "mkdir -p $DIR_DONE"
        [ ! -d $DIR_BIN ] && rlRun "mkdir -p $DIR_BIN"
        [ -f $REBOOT_DOGFILE ] && rlFail "Unexpected restart detected, please check." || rlRun "touch $REBOOT_DOGFILE"
        init_skip
        rlRun "TmpDir=\$(mktemp -d -p $DIR_ENTRY)" 0 "Creating tmp directory"
        # shellcheck disable=SC2154
        rlRun "pushd $TmpDir"
        rlRun "ps -AL -o start_time,time,tid,pid,ppid,pcpu,pmem,psr,comm | sort -k6 -rg" 0 "init process states"
    rlPhaseEnd

    run_regression

    rlPhaseStartCleanup
        rlRun "popd"
        rlLogInfo "$(get_skip_summary)"
        [ ! -f $DIR_DEBUG/DEBUG ] && rlRun "rm -r $TmpDir" 0-254 "Removing tmp directory"
        rm -f $REBOOT_DOGFILE
        rlRun "ps -AL -o start_time,time,tid,pid,ppid,pcpu,pmem,psr,comm | sort -k6 -rg" 0 "end process states"
        echo "Finish run in the end"
        echo
        pstree -nalp $(ps -C restraintd --no-headers -o pid | awk '{gsub(" ","");print}')
        echo "End Meminfo:"
        cat /proc/meminfo
        echo "End hugepage meminfo:"
        find /sys/devices/system/node -name nr_hugepages -exec cat {} \; -a -printf "%h/%f\n"
        sed -i '/reboot_dogfile/d' /usr/bin/rhts-reboot
        make reset
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
