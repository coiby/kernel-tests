#!/bin/bash
# $1 cap energy

if [ -z "$1" ]; then
        echo "usage: cap.sh energy_in_microjoules"
        exit 1
else
        energy="$1"
fi

cpu_sockets="$(lscpu | grep 'Socket(s):' | sed 's/^Socket(s):[^0-9]*\([0-9]*\)/\1/')"

(( cap_energy=energy/cpu_sockets ))

rapl_path="/sys/devices/virtual/powercap/intel-rapl"
rapl="$(ls -1 "$rapl_path" | grep 'intel-rapl:')"

#echo "energy" >  /sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw
for cpu in $rapl; do
        if ! echo "$cap_energy" > "$rapl_path/$cpu/constraint_0_power_limit_uw"; then
                dmesg | grep powercap
                echo "Writing to constraint_0_power_limit_uw has failed" >> warn.tmp
        fi
echo "$cap_energy" > "$rapl_path/$cpu/constraint_0_power_limit_uw"
done
