#!/bin/bash

# measurement time should be bigger than
# cat /sys/devices/virtual/powercap/intel-rapl/intel-rapl\:0/constraint_0_time_window_us
# which is 1 sec by default (at least on systems I have seen so far).
measurement_time=30
(( load_time=measurement_time+20 ))

# 1 no load, no cap

e_no_no="$(./energy.sh "$measurement_time")"

echo "Power consumtion on uncapped system with no load: $e_no_no microwatts"

# load, no cap

cpus="$(lscpu | grep '^CPU(s):' | sed 's/^CPU(s):[^0-9]*\([0-9]*\)/\1/')"
./load_m.sh "$load_time" "$cpus"
e_full_no="$(./energy.sh "$measurement_time")"

echo "Power consumtion on uncapped system with full load: $e_full_no microwatts"

# cap to average between full load and no load

(( e_mid=(e_no_no+e_full_no)/2 ))

echo "Going to cap the system to: $e_mid microwatts"

old_cap="$(./read_cap.sh)"
./cap.sh "$e_mid"
./load_m.sh "$load_time" "$cpus"
e_full_cap="$(./energy.sh "$measurement_time")"

echo "Power consumtion on capped system with full load: $e_full_cap microwatts"

# measured_max is maximal measured value which will not cause fail
# measured_min is minimal measured value which will not cause fail
# *12/10 - add 20% (in bash which works in integers only - we're
# using microwatts, so numbers are milions to hundreds of milions,
# so there is no problem with rounding error)
# *8/10 - substract 20%
# Previous +-10% range wasn't enough especially for computers with
# CPUID=71dec
(( measured_max=e_mid*12/10 ))
(( measured_min=e_mid*8/10 ))

if [ "$e_full_cap" -gt "$measured_max" -o "$e_full_cap" -lt "$measured_min" ]; then
        echo "FAIL: measured energy consumption doesn't match capped value."
        exit 1
fi

echo "capping back to $old_cap"
./cap.sh "$old_cap"

echo "PASS: Test passed."

#All my tests can write warnings (like non met depedencies) to this file, which wil be
#translated to warning in the Beaker.
touch warn.tmp
