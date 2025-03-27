#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/rng-jitter
#   Description: Test jitter and rngtools
#   Author: Vilem Marsik <vmarsik@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
rlPhaseStart FAIL "Functionality"
    rlShowRunningKernel
    rlRun "which dnf && export PACKAGE_MANAGER=dnf || export PACKAGE_MANAGER=yum"
    rlRun "$PACKAGE_MANAGER install -y beakerlib rng-tools jitterentropy"
    rlLogInfo "$DISTRO"
    rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
    rlLogInfo "selinug "$(getenforce)
    rlRun "cat /dev/zero | rngtest -c 100 --pipe > /dev/null" 1 "zeros fail rngtest"
    rlRun "timeout 15 rngd -f -o /dev/stdout -x hwrng -x rdrand -x tpm -O jitter:timeout:10 -O jitter:use_aes:1 | rngtest -c 100 --pipe > /dev/null"
    rlRun "cat /dev/urandom | rngtest -c 100 --pipe >/dev/null" 0 "urandom passes rngtest"
    FILE="/tmp/entropy"
    CMD=$(echo -n "rngd -n jitter -O jitter:timeout:10"; rngd -l 2>&1 | grep '^[0-9]' | cut -d\( -f2 | cut -d\) -f1 | grep -v jitter | while read A; do echo -n " -x $A"; done; echo " -f -o /dev/stdout > ${FILE}")
    rlRun "timeout 120 $CMD" 124
    rlRun "cat ${FILE} | rngtest" 0-255
    rlRun "systemctl start rngd"
    rlRun "systemctl status rngd"
rlPhaseEnd

rlPhaseStart FAIL "basic daemon tests"
    service rngd stop --no-pager >/dev/null 2>&1
    rlRun "service rngd status --no-pager" 3 "Checking if stopped"
    rlRun "service rngd start --no-pager" 0 "Starting rngd daemon"
    rlRun "service rngd status --no-pager" 0 "Checking if started"
    sleep 5
    rlRun "service rngd status --no-pager" 0 "Still running after 15s"
    service rngd stop --no-pager >/dev/null 2>&1
rlPhaseEnd

rlPhaseStart FAIL "options test"
    # check if "rngd -f" will run in foreground in a subshell
    # -> check if process runs & next command did not start
    killall -q -9 rngd
    FILE=`mktemp -u`
    ( rngd -f; touch $FILE )&
    sleep 2;
    [ -e $FILE ]
    EXISTS=$?
    killall rngd # returns true if rngd runs
    if [ $? -eq 0 ] && [ $EXISTS -ne 0 ]
    then
        rlPass "foreground run OK"
    else
        rlFail "foreground run FAILED"
    fi
    killall -q -9 rngd
    fg
    rm $FILE

    # check if "rngd -b" will run in background
    rngd -b
    killall rngd
    if [ $? -eq 0 ]
    then
        rlPass "background run OK"
    else
        rlFail "background run FAILED"
    fi
    killall -q -9 rngd
rlPhaseEnd

rlPhaseStartTest "rngtest"
    if [ "$(cat /sys/class/misc/hw_random/rng_current)" = "none" ]
    then
        rlRun "rngd -b"
        rlRun -s "rngtest -c 1000 </dev/random" "0,1" "Running rngtest"
        rlRun "killall -q -9 rngd"
    else
        rlRun -s "rngtest -c 1000 </dev/hwrng" "0,1" "Running rngtest"
    fi
    SUCCESSES=$(awk '/FIPS 140-2 successes/{print $NF}' $rlRun_LOG)
    FAILURES=$(awk '/FIPS 140-2 failures/{print $NF}' $rlRun_LOG)
    if [ "$FAILURES" -lt 100 ] ; then
        rlReport "FIPS 140-2 successes" "PASS" "$SUCCESSES"
        rlReport "FIPS 140-2 failures" "PASS" "$FAILURES"
    else
        rlReport "FIPS 140-2 successes" "FAIL" "$SUCCESSES"
        rlReport "FIPS 140-2 failures" "FAIL" "$FAILURES"
    fi
    rlFileSubmit $rlRun_LOG rngtest.out
    #rm -f $rlRun_LOG
rlPhaseEnd

rlPhaseStartTest "entropy-pool"
    rlRun "systemctl start rngd.service" 0 "Starting rngd.service"
    rlRun "systemctl -q is-active rngd.service" 0 "rngd.service is active"

    # from random(4) man page, entropy_avail maxes out now at 256 bits
    # rngd + hwrng should keep entropy_avail high all the time
    for i in {1..10}; do
        dd if=/dev/random of=/dev/null bs=1024 count=1
        ENTROPY=$(</proc/sys/kernel/random/entropy_avail)
        rlAssertGreater "Available entropy at least 128" $ENTROPY 127
        if [ "$ENTROPY" -gt 127 ]; then
            rlReport "entropy_avail" "PASS" "$ENTROPY"
        else
            rlReport "entropy_avail" "FAIL" "$ENTROPY"
        fi
        sleep 1
    done
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
