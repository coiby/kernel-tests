#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# BPF command is added in RHEL-7.6 (crash-7.2.3-8.el7) and RHEL-8.0
# Bug 1559758 - [RHEL7] crash needs to allow extraction of BPF programs from the vmcore
# Bug 1572524 - [RHEL8] crash needs to allow extraction of BPF programs from the vmcore

analyse()
{
    CheckSkipTest crash 7.2.3-8 && return

    CheckVmlinux
    GetCorePath

    local crash_cmd crash_output
    crash_cmd="${K_TESTAREA}/crash-bpf-simple.cmd"
    crash_output="${K_TESTAREA}/crash-bpf-simple.cmd.log"
    local prog_id map_id

    # simple bpf test, get a program ID
    cat <<EOF > "$crash_cmd"
bpf
exit
EOF
    RhtsSubmit "$crash_cmd"
    Log "Run crash bpf against the vmcore. "

    # shellcheck disable=SC2154
    Log "# crash -i \"$crash_cmd\" \"${vmlinux}\" \"${vmcore}\""
    crash -i "$crash_cmd" "${vmlinux}" "${vmcore}" > "$crash_output" 2>&1

    RhtsSubmit "$crash_output"

    if ! grep -q -A 1 BPF_PROG "$crash_output"; then
        Error "Failed to run bpf command. Please read $(basename $crash_output) for details."
        return
    fi

    prog_id=$(grep BPF_PROG -A 1 "$crash_output" | awk '{w=$1} END{print w}')
    map_id=$(grep BPF_MAP -A 1 "$crash_output" | awk '{w=$1} END{print w}')
    if [[ ! $prog_id =~ ^[0-9]+$ ]] || [[ ! $map_id =~ ^[0-9]+$ ]]; then
        Error "Failed to get program id or map id. Please read $(basename $crash_output) for details."
        return
    fi

    crash_cmd="${K_TESTAREA}/crash-bpf.cmd"
    cat <<EOF > "$crash_cmd"
help bpf
bpf
bpf -p $prog_id
bpf -m $map_id
bpf -p $prog_id -j
bpf -p $prog_id -t
bpf -p $prog_id -T
bpf -m $map_id -s
bpf -p $prog_id -s
bpf -P
bpf -M
bpf -PM -jTs
exit
EOF

    CrashCommand "" "${vmlinux}" "${vmcore}" "$(basename $crash_cmd)"
}

#+---------------------------+
# $1 is the test phase name
MultihostStage "$(basename "${0%.*}")" "analyse"

