#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of misc/signal-test
#   Description: Test the default behavior of signals
#   Author: Yumei Huang <yuhuang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TEST="misc/signal-test"

result=FAIL

gcc -o signal_test signal.c
./signal_test

if [ "$?" -eq "0" ]; then
    result=PASS
else
    result=FAIL
fi

rstrnt-report-result $TEST $result
