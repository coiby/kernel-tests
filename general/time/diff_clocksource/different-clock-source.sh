#!/bin/bash -x

exec 3</sys/devices/system/clocksource/clocksource0/available_clocksource

#while read -u3 clk; do
#	echo $clk > /sys/devices/system/clocksource/clocksource0/current_clocksource
#	./gettimeofday
#done

read -u3 clk
echo $clk | sed -s 's/ /\n/g' > /tmp/temp

while read i
do
    echo $i > /sys/devices/system/clocksource/clocksource0/current_clocksource
    ./gettimeofday
done < /tmp/temp
