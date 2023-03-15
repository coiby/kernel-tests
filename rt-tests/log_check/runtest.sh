#!/bin/bash

export TEST="rt-tests/log_check"

cat > list-general.txt <<EOF
cut here
call trace:
traceback
EOF
cat > list-kernel.txt <<EOF
\([^de]\|^\)bug:[[:space:]]
oops:[[:space:]]
WARNING:.*at kernel
EOF
cat > list-locking.txt <<EOF
circular locking dependency
inconsistent lock state
EOF
cat > list-hung.txt <<EOF
blocked for more than
rcu_preempt self-detected stall
EOF
cat > list-oom.txt <<EOF
oom-killer
sysrq: show memory
rt_mutex_slowlock_block
EOF

function log_check()
{
    declare fail_strings=$1
    declare result="PASS"

    if dmesg | grep -q -i -f $fail_strings ; then
        echo "Found a failure-indicating string from ${fail_strings}:" | tee -a $OUTPUTFILE
        dmesg | grep -A 20 -i -f $fail_strings
        rstrnt-report-result "log_check_dmesg" "WARN" "1"
        dmesg > dmesg.log
        rstrnt-report-log -l dmesg.log
        result="FAIL"
    fi

    if journalctl | grep -q -i -f $fail_strings ; then
        echo "Found a failure-indicating string from ${fail_strings}:" | tee -a $OUTPUTFILE
        journalctl | grep -A 20 -i -f $fail_strings
        rstrnt-report-result "log_check_journalctl" "WARN" "1"
        journalctl > journal.log
        rstrnt-report-log -l journal.log
        result="FAIL"
    fi

    rstrnt-report-result "$TEST/${fail_strings//.txt}" "$result" 0

    rm -f $fail_strings
}

function runtest()
{
    if ! uname -r | grep -q debug; then
        # skip general checks on a debug kernel
        log_check "list-general.txt"
    fi
    log_check "list-kernel.txt"
    log_check "list-locking.txt"
    log_check "list-hung.txt"
    log_check "list-oom.txt"
}

runtest
exit 0
