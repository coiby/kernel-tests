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

sys_signals=$(kill -l | tr ' ' '\n' | grep '^SIG' | awk '{print $1}')
sig_count=$(echo "$sys_signals" | wc -w)
if [ $sig_count -ne 62 ]; then
    rstrnt-report-result $TEST $result
    exit 0
fi

man_signals=$(man 7 signal | awk -v sys_signals="$sys_signals" '
BEGIN { in_table = 0; after_header = 0 }
# Find start of signal table
/Signal      Standard   Action   Comment/ { in_table = 1; next }
/────────────────────/ { if (in_table) after_header = 1; next }
/The signals SIGKILL and SIGSTOP/ { in_table = 0 }

# Process signal lines
in_table && after_header && /^\s{1,}SIG/ {
    if (index(sys_signals, $1) > 0)
        printf("%s %s\n", $1, $3)
}
')

gcc -o signal_test signal.c

echo -e "$man_signals" | ./signal_test

if [ "$?" -eq "0" ]; then
    result=PASS
else
    result=FAIL
fi

rstrnt-report-result $TEST $result
