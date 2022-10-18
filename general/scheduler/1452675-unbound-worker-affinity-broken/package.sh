#!/bin/bash
find /sys/devices/system/cpu/ -name physical_package_id -exec grep -wq ${1:-1} {} \; -printf "%p\n" | egrep -wo "cpu[0-9]+" | egrep -o "[0-9]+" | sort -n | awk 'BEGIN{ORS=" "}{print $1}' | sed 's/ $//'
