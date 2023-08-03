#!/bin/bash
# This file is used for custom bpf test configurations for an internal gitlab instance

# shellcheck disable=SC1090,SC1091 # $CDIR is imported by the main include script.
. "$CDIR"/include/net.sh

do_bpf_run()
{
    declare -a tests=(
        "bpf:test_verifier"
        "bpf:test_lpm_map"
        "bpf:test_lru_map"
        "bpf:test_tag"
        "bpf:test_verifier_log"
        "bpf:test_bpftool.sh"
        "bpf:test_bpftool_metadata.sh"
        "bpf:test_ftrace.sh"
        "bpf:test_dev_cgroup"
        "bpf:test_cgroup_storage"
        "bpf:test_sysctl"
        "bpf:test_cpp"
        "bpf:test_maps"
    )

    total_num=${#tests[@]}
    num=0

    for test in "${tests[@]}"; do
        num=$((num + 1))
        RunKSelfTest "${test}"
        ret=$?
        check_result "$num" "$total_num" "${test}" "$ret"
    done
}
