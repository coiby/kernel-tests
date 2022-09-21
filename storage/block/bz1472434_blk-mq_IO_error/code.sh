#!/bin/bash

DEV=$1
COUNT=48

echo "16" >/sys/block/$DEV/queue/nr_requests
while [ "$COUNT" != "0" ]; do
	dd if=/dev/$DEV of=/dev/null bs=4096c ibs=4096c skip=$COUNT iflag=direct count=1 &
	COUNT=`expr $COUNT - 2`
done

wait
