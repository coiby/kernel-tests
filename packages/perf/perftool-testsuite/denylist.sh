#!/bin/bash

# This is a list of test exceptions for perftool-testsuite, see
# expected_result() in runtest.sh to see how it is currently used.

# format:  RESULT  ARCH,[ARCH2,]*  KERNEL_VERSION_START  KERNEL_VERSION_END  test_name
# test_name may specify a class of tests; any test containing it in the
# full name will also be considered to expect RESULT.

DENYLIST=()

DENYLIST+=("FAIL  aarch64,                             4.18.0      9.99.9      perf_archive :: test_basic :: archive creation")

DENYLIST+=("FAIL  x86_64,ppc64le,                      4.18.0      9.99.9      perf_c2c")

DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_list :: test_basic :: basic execution (output regexp parsing)")
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_list :: test_basic :: list pmu (output regexp parsing)")

DENYLIST+=("FAIL  x86_64,ppc64le,                      4.18.0      9.99.9      perf_mem")

DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_probe :: test_adding_kernel :: listing added probe :: perf probe -l (output regexp parsing)")
DENYLIST+=("FAIL  x86_64,                              4.18.0      9.99.9      perf_probe :: test_adding_kernel :: function with retval :: add")
DENYLIST+=("FAIL  ppc64le,x86_64,                      4.18.0      9.99.9      perf_probe :: test_adding_kernel :: function with retval :: record")
DENYLIST+=("FAIL  x86_64,                              4.18.0      9.99.9      perf_probe :: test_adding_kernel :: function argument probing :: script")
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_probe :: test_listing :: kernel variables list (output regexp parsing)")
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_probe :: test_probe_syntax :: custom named probe :: list (output regexp parsing)")

DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_record :: test_basic :: -k mono crash")
DENYLIST+=("FAIL  aarch64,                             4.18.0      9.99.9      perf_record :: test_evlist :: various events :: record bus-cycles (output regexp parsing)")

DENYLIST+=("FAIL  s390x,                               4.18.0      9.99.9      perf_stat :: test_advanced_options :: delay event cpu-clock values OK (output regexp parsing)")
DENYLIST+=("FAIL  aarch64,                             4.18.0      9.99.9      perf_stat :: test_hw :: k+u=ku check :: event")
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_stat :: test_powerpc_hv_24x7 :: event")

# generally occuring issues for RHEL-8
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_archive :: test_basic :: archive sanity (contents)")

DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_diff :: test_basic :: basic execution - diff (output regexp parsing)")

DENYLIST+=("FAIL  aarch64,                             4.18.0      9.99.9      perf_probe :: test_advanced :: function string argument kprobing :: script (output regexp parsing)")
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_probe :: test_advanced :: function string argument kprobing")
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_probe :: test_listing :: kernel lines list")
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_probe :: test_listing :: kernel source lines list")

DENYLIST+=("FAIL  s390x,aarch64,ppc64le,x86_64,        4.18.0      9.99.9      perf_stat :: test_hw_breakpoints :: kspace address readwrite mem")
DENYLIST+=("FAIL  s390x,aarch64,ppc64le,x86_64,        4.18.0      9.99.9      perf_stat :: test_hw_breakpoints :: kspace address execution mem")
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_stat :: test_record_report :: diff")

### newly added issues
DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_kmem :: test_basic :: stat")

DENYLIST+=("FAIL  ppc64le,                             4.18.0      9.99.9      perf_sched :: test_basic :: sched replay")
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,               4.18.0      9.99.9      perf_sched :: test_timehist :: --summary unique tasks count check")
DENYLIST+=("FAIL  aarch64,ppc64le,s390x,               4.18.0      9.99.9      perf_sched :: test_timehist :: --wakeups (output regexp parsing)")

DENYLIST+=("FAIL  aarch64,ppc64le,s390x,x86_64,        4.18.0      9.99.9      perf_script :: test_header :: script (output regexp parsing)")

DENYLIST+=("FAIL  aarch64,                             4.18.0      9.99.9      perf_trace :: test_basic :: attach process (output regexp parsing)")

