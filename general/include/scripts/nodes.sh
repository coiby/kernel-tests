#!/bin/bash
# Input the memory you need in MB. Then script outputs the node list
# with minimal nodes to meet the mem requirement. If not numa support
# (no sysfs interface in s390x), output "0" directly.
find /sys/devices/system/node/  -name meminfo -exec cat {} \; |
awk -v need_mem=$1 '
BEGIN{curr=0;snode=""; node=0}
/MemFree/ {
        node=$2
        if ($4 != "0") {
                if (curr < need_mem)
                        snode=snode","node
        }
        curr+=$4/1024
}
END{gsub("^,","", snode);if (snode=="") snode=0; printf("%s\n", snode)}'
