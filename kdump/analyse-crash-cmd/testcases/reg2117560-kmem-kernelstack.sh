#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2117560 - sub-command defects on upstream crash build
# Fixed in 8.8 (crash-7.3.2-4.el8) and 9.1 (crash-8.0.2-1.el9)
# This case is to test the first anomally reported in the bug
Analyse() {
    if [ "$ALLOW_SKIP" = "true" ]; then
        if [ "${RELEASE}" -lt 8 ]; then
            Skip "Test is not applicable to RHEL7 or older releases"
        elif [ "${RELEASE}" -eq 8 ]; then
            CheckSkipTest crash 7.3.2-4 && return
        elif [ "${RELEASE}" -eq 9 ]; then
            CheckSkipTest crash 8.0.2-1 && return
        fi
    fi

    CheckVmlinux
    GetCorePath

    local bt_in="reg2117560_bt.cmd"
    local bt_out="reg2117560_bt.out"

    cat <<EOF >"${bt_in}"
bt
exit
EOF

    # shellcheck disable=SC2154
    crash "${vmlinux}" "${vmcore}" -i "${bt_in}" > "${bt_out}"
    if [[ "$?" -ne "0" ]];then
        Error "Failed to run crash command."
    fi

    # RES stores the address of panic
    local res="$(awk -F'[][]' '/panic at/ {print $2}' "${bt_out}")"
    local pid="$(awk -F' ' '/PID:/ {print $1}' "${bt_out}")"

    # kmem the panic address
    local kmem_in="reg2117560_kmem.cmd"
    local kmem_out="reg2117560_kmem.out"
    cat <<EOF >"${kmem_in}"
kmem $res
exit
EOF

    crash "$vmlinux" "$vmcore" -i "${kmem_in}" > "${kmem_out}"
    ret=$?

    RhtsSubmit "$(pwd)/${bt_in}"
    RhtsSubmit "$(pwd)/${bt_out}"
    RhtsSubmit "$(pwd)/${kmem_in}"
    RhtsSubmit "$(pwd)/${kmem_out}"

    # crash> bt
    # PID: 4735   TASK: ffff0000c42bbe40  CPU: 0   COMMAND: "runtest.sh"
    #  #0 [ffff8000121339a0] machine_kexec at ffffdb21d91607ec
    #  #1 [ffff8000121339d0] __crash_kexec at ffffdb21d929c8c4
    #  #2 [ffff800012133b60] panic at ffffdb21d9cf47c8
    #..

    # Before the fix:
    # crash> kmem ffff800012133b60
    # VMAP_AREA         VM_STRUCT                 ADDRESS RANGE                SIZE
    # ffff94eb9102c640  ffff94eb9102b140  ffffb7efce9b8000 - ffffb7efce9bd000    20480
    # ...

    # Expect Result: Print the task it belongs to
    # crash> kmem ffff800012133b60
    # ...
    #     PID: 4735
    # COMMAND: "runtest.sh
    # TASK: ffff0000c42bbe40  [THREAD_INFO: ffff0000c42bbe40]
    # CPU: 0

    if [ "$ret" -ne "0" ];then
        Error "Crash command return non-zero value."
        return
    fi

    # Check PID: to see whether kmem reported kernel stack or not
    if ! grep -q "PID: $pid" "${kmem_out}"; then
        Error "Failed. kmem didn't show the task it belongs to. Check ${kmem_out} for details."
    else
        Log "Pass. 'kmem addr' print the task it belongs to. Check ${kmem_out} for details."
    fi
}

#+---------------------------+
MultihostStage "$(basename "${0%.*}")" Analyse
