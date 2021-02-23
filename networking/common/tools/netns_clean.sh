#!/bin/bash

# clean netns env
for net in $(ip netns list | awk '{print $1}'); do
	ip netns del $net
done
modprobe -r veth
# br_netfilter would stop bridge to be removed as it depends on bridge
modprobe -r br_netfilter
modprobe -r bridge
exit 0
