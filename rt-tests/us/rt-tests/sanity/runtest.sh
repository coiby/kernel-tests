#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# shellcheck source=/dev/null

# Source rt common functions
. ../../../include/lib.sh || exit 1

export TEST="rt-tests/us/rt-tests/sanity"
export nrcpus rhel_x

(( rhel_x >= 9 )) && rt_tests_pkgname="realtime-tests" || rt_tests_pkgname="rt-tests"

if stat /run/ostree-booted > /dev/null 2>&1; then
        PKGMGR="rpm-ostree -Ay --idempotent --allow-inactive install"
elif [[ -x /usr/bin/dnf ]]; then
        PKGMGR="dnf -y --skip-broken install"
else
        PKGMGR="yum -y --skip-broken install"
fi

function test_run()
{
    oneliner "$PKGMGR $rt_tests_pkgname"

    # Note: test changing the runtime/deadline/period parameters of cyclicdeadline's
    #       current scheduling policy for SCHED_DEADLINE
    phase_start_test cyclicdeadline
    run --lol "cyclicdeadline 1>/dev/null 2>&1 &"
    run --lol "sleep 1"
    deadline_pid=$(chrt -a -p "$(pgrep cyclicdeadline)" | grep SCHED_DEADLINE | grep -o -P "(?<=pid ).*(?='s)")
    run "chrt -T 580000 -P 990000 -D 990000 -d -p 0 $deadline_pid"
    run "chrt -a -p \"$(pgrep cyclicdeadline)\""
    run "chrt -a -p \"$(pgrep cyclicdeadline)\" | grep '580000/990000/990000'"
    run --lol "pkill -9 cyclicdeadline"
    phase_end

    phase_start_test cyclictest
    # (1) basic 30s run with smp
    run "cyclictest --smp -umq -p95 --duration=30s"
    # (2) test tracemark option functions [1753005]
    run "cyclictest -i 100 -umq -p95 -t 4 -b 1 --tracemark --duration=30s"
    # (3) test threads > cpu count [1749956]
    run "cyclictest -t $(( nrcpus * 2 )) -q --duration=10s"
    phase_end

    oneliner "deadline_test -i 1000"

    oneliner "hackbench --process --groups 36 --loops 1000 --datasize 1000"

    # Note: threshold arbitrarily picked, because non-tuned systems may not meet
    #       the lower 10us default threshold.  We are more interested in
    #       sanity/functionality than performance in this test.
    oneliner "hwlatdetect --duration=30s --threshold=2000"

        if rpm -ql "$rt_tests_pkgname" | grep -q '/usr/bin/oslat' ; then
        declare duration_flag="--duration"
        oslat --help | grep -q '\-\-runtime' && duration_flag="--runtime"
        oneliner "oslat --cpu-list 1 --rtprio 1 $duration_flag 30s"
    fi

    oneliner "pi_stress --quiet --duration=30"

    # Note: likely that no inversion will occur, but we will still verify the
    #       process at least runs and exits successfully. A timeout is added so
    #       that if this program hangs, it will not abort the test case.
    oneliner "timeout 5m pip_stress"

    oneliner "pmqtest --loops=1000 --interval=1000 --prio=99"

    oneliner "ptsematest --affinity --loops=1000 --interval=1000 --prio=99 --threads"

    if rpm -ql "$rt_tests_pkgname" | grep -q '/usr/bin/queuelat' ; then
        oneliner "queuelat -m 20us -c 100 -p 100 -f 1000 -t 60s"
    fi

    oneliner "rt-migrate-test $nrcpus"

    # Note: many of the /proc/sys/kernel/* interfaces do not exist in RHEL-8+
    oneliner "signaltest -b 20us -l 100 -q -t 10 -m -v"

    if rpm -ql "$rt_tests_pkgname" | grep -q '/usr/bin/ssdd' ; then
        # Note: ssdd is expected to finish within 40s under most scenarios, the
        # timeout is just a safe-belt for possible unresponsive situations
        oneliner "timeout --preserve-status -k 60s -s SIGINT -v 40s ssdd 10 10000"
    fi

    oneliner "svsematest -a -b 20us -f -i 100 -l 100 -S"
}

test_run
exit 0
