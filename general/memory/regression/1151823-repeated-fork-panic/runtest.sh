#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: This is a reproducer for bz1151823
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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



STRESS=${STRESS:-no}
WAITTIME=${WAITTIME:-300}
TIMEFRAME=${TIMEFRAME:-60}
REPRODUCER="fork_snake"


setup_env()
{
    if ! rlIsRHEL ">=6.6" && ! rlIsCentOS ">6.6"; then
        echo "fixed in kernel-2.6.32-589.el6, 6.6.z 6.7.z" | tee -a $OUTPUTFILE
        rstrnt-report-result Test_Skipped PASS 99
        exit 0
    fi

    if [ -f SETUP_FLAG ]; then
        return 0;
    fi
    touch SETUP_FLAG

    rlPhaseStartSetup
    rlRun "gcc ${REPRODUCER}.c -o ${REPRODUCER}"
    if [ $STRESS == "yes" ]; then
        rlRun "grubby --args=mem=500M --update-kernel=`grubby --default-kernel`"
        zipl 2>&1 > /dev/null
        rstrnt-reboot
    fi
    rlPhaseEnd

}


cleanup_env()
{
    if [ -f CLEANUP_FLAG ]; then
        rm *FLAG
        return 0;
    fi
    touch CLEANUP_FLAG;

    rlPhaseStartCleanup
    rlAssertExists ./TESTDONE_FLAG
    if [ $STRESS == "yes" ]; then
        rlRun "grubby --remove-args=mem --update-kernel=`grubby --default-kernel`"
        zipl 2>&1 > /dev/null
        rstrnt-reboot
    fi

    rlRun 'cat /proc/meminfo  /proc/slabinfo | grep -e MemTotal -e MemFree -e SUnreclaim -e anon_vma'
    while [ $? == 0 ]; do
        pkill $REPRODUCER
        ps -C $REPRODUCER
    done
    rm -f *FLAG
    swapon -a
    rlPhaseEnd
}


run_test()
{
    local anon_vma_objs=0
    local anon_vma_objs_max=0
    local start_time=`date '+%s'`
    local now_time=$start_time

    if [ -f RUNTEST_FLAG ]; then
        return 0;
    fi
    touch RUNTEST_FLAG;

    rlPhaseStartTest
    swapoff -a
    rlRun 'echo 3 > /proc/sys/vm/drop_caches'
    rlRun 'cat /proc/meminfo  /proc/slabinfo | grep -e MemTotal -e MemFree -e SUnreclaim -e anon_vma'
    rlRun "./${REPRODUCER}"

    # run reproducer in the backgrond,
    #   return if anon_vma didn't grow in $TIMEFRAME secs
    while [ true ]; do
        anon_vma_objs=`cat /proc/slabinfo | grep -w anon_vma | awk '{print $3}'`
        if [ $anon_vma_objs -gt $anon_vma_objs_max ]; then
            anon_vma_objs_max=$anon_vma_objs
            start_time=`date '+%s'`
        fi
        now_time=`date '+%s'`
        if [ $((now_time-start_time)) -gt $TIMEFRAME ]; then
            break
        fi
    done &


    # wait till slabs do not grow or panic
    if [ $STRESS == "yes" ]; then
        wait
        touch TESTDONE_FLAG
        rlPhaseEnd
        return 0
    fi


    # wait till slabs do not grow in $WAITTIME secs
    while [ $WAITTIME -gt 0  ]; do
        if [ `jobs -rl  | wc -l` -eq 0 ]; then
            break
        fi
        WAITTIME=$((WAITTIME-1))
        sleep 1
    done
    rlAssertGreater "Assert not expired, WAITTIME=$WAITTIME" $WAITTIME 0

    touch TESTDONE_FLAG
    rlPhaseEnd
}


rlJournalStart
    setup_env
    run_test
    cleanup_env
rlJournalEnd
rlJournalPrintText

