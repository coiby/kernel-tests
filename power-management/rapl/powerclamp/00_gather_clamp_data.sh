#!/bin/bash
# Measures the power consumption during different loads and clamping levels.
# Exports these power consumtions in file $power_file for next tests.
#
# $1 = runtime

# Author:  Erik Hamera alias lhc
# contact: lhc (at) redhat (dot) com
#          ehamera (at) redhat (dot) com
# License: GNU GPL

# hardcoded files for data output

# hardcoded file with power consumptions

power_file="power.tmp"

# hardcoded file for all warnings - the script will end with 0 (PASS) in case of warning
# warnings are handled at the end of testcase

warn_file="warn.tmp"

#for debug reasons - make cat of this file pass
touch "$warn_file"

if [ -n "$1" ]; then
        runtime="$1"
else
        runtime="300"
fi

cores="$(cat /proc/cpuinfo |grep processor |wc -l)"

echo "Detected $cores cores."

clampdev="$(grep 'intel_powerclamp' /sys/class/thermal/cooling_device*/type | sed 's/\(.*[^0-9][0-9]*\/\)type:.*/\1cur_state/')"

if [ -z "$clampdev" ]; then
        echo 'Clamping device has not found.'
        echo 'Clamping device has not found.' >> "$warn_file"
        exit 0
fi

# IMPORTANT NOTE - read before modify this piece of code
#
# these measurements: 0, clamp and full - should be sorted in ascending order
# of expected power consumption.
# The 01_compare_loads.sh checks if reported power consumption is increasing.

for x in 0 clamp full; do
        if [ "$x" == 'clamp' ]; then
                i="$cores"
                #enable clamping - idle 49% of power
                echo 49 > "$clampdev"
        elif [ "$x" == 'full' ]; then
                #disable clamping
                echo 0 > "$clampdev"
                i="$cores"
        else
                i="$x"
        fi

        echo "Trying $i threads of load."
        ./load_m.sh "$runtime" "$i"
        ./energy.sh "$runtime" >> "$power_file"

        sleep 20
done

#disable clamping
echo 0 > "$clampdev"
