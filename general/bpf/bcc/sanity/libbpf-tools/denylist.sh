#!/bin/bash

# This is a list of test exceptions for perftool-testsuite, see
# expected_result() in runtest.sh to see how it is currently used.

# format:  RESULT  ARCH,[ARCH2,]*  KERNEL_VERSION_START  KERNEL_VERSION_END  test_name
# test_name may specify a class of tests; any test containing it in the
# full name will also be considered to expect RESULT.

DENYLIST=()

# s390x
DENYLIST+=("FAIL  s390x, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  s390x, 0.0.0 9.99.9  bpf-ksnoop")
# x86_64
DENYLIST+=("FAIL  x86_64, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  x86_64, 0.0.0 9.99.9  bpf-ksnoop")
DENYLIST+=("FAIL  x86_64, 0.0.0 9.99.9  bpf-drsnoop")
# aarch64
DENYLIST+=("FAIL  aarch64, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  aarch64, 0.0.0 9.99.9  bpf-ksnoop")
DENYLIST+=("FAIL  aarch64, 0.0.0 9.99.9  bpf-readahead")
# ppc64le
DENYLIST+=("FAIL  ppc64le, 0.0.0 9.99.9  bpf-javagc")
DENYLIST+=("FAIL  ppc64le, 0.0.0 9.99.9  bpf-ksnoop")
DENYLIST+=("FAIL  ppc64le, 0.0.0 9.99.9  bpf-readahead")
DENYLIST+=("FAIL  ppc64le, 0.0.0 9.99.9  bpf-syncsnoop")
