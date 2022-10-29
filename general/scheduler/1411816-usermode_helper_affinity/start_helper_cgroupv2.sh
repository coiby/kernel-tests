#!/bin/bash
set -e

# cgroup v2 don't have 'release_agent' feature', here use request_module() to
# do the macvtap

lsmod | grep macvtap && rmmod macvtap
ip link add br1411816 type bridge
ip link add link br1411816 macvtap1411816 type macvtap

ip link del macvtap1411816
ip link del br1411816

