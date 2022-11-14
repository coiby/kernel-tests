#!/bin/bash
rapl_path="/sys/devices/virtual/powercap/intel-rapl"
rapl="$(ls -1 "$rapl_path" | grep 'intel-rapl:')"

e=0
for cpu in $rapl; do
        e_cpu="$(cat "$rapl_path/$cpu/constraint_0_power_limit_uw")"
        (( e+=e_cpu ))
done

echo "$e"
