#!/bin/bash
for i in $(seq $(nproc)) # 2000 for 100% reproduce reate, but need to manual run
do
	systemd-run --scope dd if=/dev/zero of=/dev/null &
done

echo t > /proc/sysrq-trigger &
echo t > /proc/sysrq-trigger &
