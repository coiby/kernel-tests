#!/bin/bash
# $1 time for measurement

if [ -z "$1" ]; then
        time=30
        #Default is 30 secs
else
        time="$1"
fi


rapl_path="/sys/devices/virtual/powercap/intel-rapl"
rapl="$(ls -1 "$rapl_path" | grep 'intel-rapl:')"

e1=0
for cpu in $rapl; do
        e_cpu="$(cat "$rapl_path/$cpu/energy_uj"*)"
        (( e1+=e_cpu ))
done

sleep "$1"

e2=0
for cpu in $rapl; do
        e_cpu="$(cat "$rapl_path/$cpu/energy_uj"*)"
        (( e2+=e_cpu ))
done

(( e=(e2-e1)/time))

echo "$e"
