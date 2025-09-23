#!/bin/bash

# This is a list of test exceptions for bcctool-testsuite.

# format:  RESULT  ARCH,[ARCH2,]*  BCC_VERSION_START  BCC_VERSION_END  test_name
# test_name may specify a class of tests; any test containing it in the
# full name will also be considered to expect RESULT.

DENYLIST=()

# s390x
DENYLIST+=("FAIL  s390x, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  s390x, 0.34.0 9.99.9  bpf-ksnoop :: libbpf: prog 'kprobe_entry': BPF program load failed: Permission denied :: RHEL-93852")
# x86_64
DENYLIST+=("FAIL  x86_64, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  x86_64, 0.34.0 9.99.9  bpf-ksnoop :: libbpf: prog 'kprobe_entry': BPF program load failed: Permission denied :: RHEL-93852")
# aarch64
DENYLIST+=("FAIL  aarch64, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  aarch64, 0.34.0 9.99.9  bpf-ksnoop :: libbpf: prog 'kprobe_entry': BPF program load failed: Permission denied :: RHEL-96166/RHEL-93852")
DENYLIST+=("FAIL  aarch64, 0.34.0 9.99.9  bpf-readahead :: failed to attach to access functions :: RHEL-105474")
# ppc64le
DENYLIST+=("FAIL  ppc64le, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  ppc64le, 0.34.0 9.99.9  bpf-ksnoop :: libbpf: prog 'kprobe_entry': BPF program load failed: Permission denied :: RHEL-93852")
DENYLIST+=("FAIL  ppc64le, 0.34.0 9.99.9  bpf-readahead :: failed to attach to access functions :: RHEL-105474")
DENYLIST+=("FAIL  ppc64le, 0.32.0 9.99.9  bpf-syncsnoop :: libbpf: failed to determine tracepoint 'syscalls/sys_enter_sync_file_range' perf event ID: No such file or directory; failed to attach BPF object :: RHEL-93854/RHEL-78171")
