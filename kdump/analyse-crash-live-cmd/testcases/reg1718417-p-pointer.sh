#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1718417 - please backport fix for 'p' command regression
# Fixed in RHEL-8.1 crash-7.2.6-2.el8
analyse()
{
    CheckSkipTest crash 7.2.6-2 && return

    # Check command output of this session.
    cat <<EOF > "set.cmd"
set 1
exit
EOF
    crash -i set.cmd | tee set.out
    RhtsSubmit "$(pwd)/set.out"
    local task_addr
    task_addr=$(grep "TASK:" set.out | tail -n 1 | awk '{print $2}')

    # Run p commands with parenthesis and pointer with/without a space
    # Before the fix, it will report "syntax error".
    # For exmaple,
    # crash> p (struct task_struct *)0xffff888596b9af80
    # A syntax error in expression, near `0xffff888596b9af80'.
    # p: gdb request failed: p (struct task_struct *)0xffff888596b9af80 0xffff888596b9af80
    cat <<EOF > "p_pointer.cmd"
p (struct task_struct *)0x${task_addr}
p (struct task_struct *) 0x${task_addr}
p ((struct task_struct *)0x${task_addr})->pid
p ((struct task_struct *) 0x${task_addr})->pid
exit
EOF

    crash -i p_pointer.cmd | tee p_pointer.out
    RhtsSubmit "$(pwd)/p_pointer.cmd"
    RhtsSubmit "$(pwd)/p_pointer.out"

    ValidateCrashOutput "$(pwd)/p_pointer.out"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse,