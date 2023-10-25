#!/bin/bash
# This file is used for Real Time kernel related tests configurations.

# Skip kselftests if the running kernel-rt is debug variant
if uname -r | grep rt | grep -q debug; then
    test_skip_exit "Detected kernel-rt-debug: skipping kselftests. Please run against kernel-rt instead."
    return 1
fi

do_bpf_config()
{
    # bz1969582 - the bpf:test_progs tests hit an expected mmap_zero avc
    # denial, unless we first turn mmap_low_allowed on
    echo "=== Setting mmap_low_allowed on ===" | tee -a $OUTPUTFILE
    setsebool -P mmap_low_allowed on
}

do_bpf_reset()
{
    # after testing completes, turn mmap_low_allowed off again
    echo "=== Setting mmap_low_allowed off ===" | tee -a $OUTPUTFILE
    setsebool -P mmap_low_allowed off
}

do_memfd_config()
{
    # install fuse package to provide fusermount for memfd:run_fuse_test.sh
    which fusermount && return 0
    echo "=== Installing package dependency: fuse ===" | tee -a $OUTPUTFILE
    $pkg_mgr $pkg_mgr_inst_string fuse
    which fusermount && return 0 || return 1
}

do_default_config()
{
    # if no TEST_ITEMS are specified, specific do_*_config functions
    # will not be called - do that here
    do_bpf_config
    do_memfd_config
}

do_default_reset()
{
    # if no TEST_ITEMS are specified, specific do_*_reset functions
    # will not be called - do that here
    do_bpf_reset
}

# The following test cases defined in $rtskips are automatically excluded
# from kernel-rt kselftests due to the known issues detailed below.  While
# a handful of them could be classified as system setup issues, there is
# minimal capacity in comitting to resolve or debug these all individually,
# and as such, we shall simply skip such tests.
rtskips=(
# expected to fail: "On RT enabled kernels run-time allocation of all trace
# type programs is strictly prohibited due to lock type constraints."
bpf:test_verifier
# occasional failure on IPv6 encap test
bpf:test_lwt_ip_encap.sh
# occasional failure with malloc(): invalid size (unsorted)
bpf:test_netcnt
# traceback with 3 BPF maps loaded, expected 2
bpf:test_offload.py
# occasionally hangs the system and causes remaining cases to abort
bpf:test_xsk.sh
# unstable on kernel-rt, several sub-tests fail without any indicative logs
bpf:test_tunnel.sh
# occasionally hits the maximum timeout
net:fib_nexthops.sh
# Error: TC classifier not found, error talking to the kernel
net:fib_tests.sh
# TEST: rule4 del by pref: tos 0x10 / TEST: rule6 del by pref: tos 0x10
net:fib_rule_tests.sh
# RTNETLINK answers: No such file or directory, when running command:
# ip -netns host-1 l2tp add tunnel tunnel_id 1041 peer_tunnel_id 1042 \
#   encap ip local 10.1.1.1 remote 10.1.2.1
net:l2tp.sh
# FAIL - got ICMP response from , should be 192.0.0.8 - during command:
#   ip netns exec ns1 ping -w 3 -i 0.5 172.16.1.1
net:icmp.sh
# IPv4 large may fail with incorrect number of packets
net:gro.sh
# Error: Specified qdisc not found, several link failures
net/mptcp:mptcp_join.sh
# bz2096948: BUG: scheduling while atomic: swapper/1/0/0x00000002
net:udpgro_fwd.sh
# ERROR: ns2-L4PDHwvX did not pick up tcp connection from peer
netfilter:conntrack_tcp_unreplied.sh
)
export SKIP_TARGETS="$SKIP_TARGETS ${rtskips[*]}"
