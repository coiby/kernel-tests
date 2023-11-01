#!/bin/bash
# Prepares data (output of perf with different loads) for next tests. Runs each
# load for defined time, where maximum is 8 runs to clamp down the time.
# It runs 0 - (n-1) threads where n is number of CPU cores. If n>8, some numbers
# are omitted (see thread_numbers.py).
#
# $1 = runtime

# Author:  Erik Hamera alias lhc
# contact: lhc (at) redhat (dot) com
#          ehamera (at) redhat (dot) com
# License: GNU GPL

# hardcoded files for data output
energy_file="energy_test_output_"
frequency_file="frequency_test_output_"

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

#on some systems (RHEL 6.8 for example) modules must be loaded manually
./init_machine.sh

clampdev="$(grep 'intel_powerclamp' /sys/class/thermal/cooling_device*/type | sed 's/\(.*[^0-9][0-9]*\/\)type:.*/\1cur_state/')"

if [ -z "$clampdev" ]; then
        echo 'Clamping device has not found.'
        echo 'Clamping device has not found.' >> "$warn_file"
        exit 0
fi

# IMPORTANT NOTE - read before modify this piece of code
#
# these strings: 0, full and clamp* will propagate info filenames, which will be sorted
# alphabetically to 0, clamp*, full and then checked if reported power consumption is
# increasing by 01_compare_loads.sh
for x in 0 full clamp_5 clamp_10 clamp_15 clamp_20 clamp_25 clamp_30 clamp_35 clamp_40 clamp_45 clamp_49; do
        if echo "$x" | grep 'clamp' >/dev/null; then
                i="$cores"
                #enable clamping
                c="$(echo "$x" | sed 's/^clamp_//')"
                echo "$c" > "$clampdev"
        elif [ "$x" == 'full' ]; then
                echo "0" > "$clampdev"
                i="$cores"
        else
                echo "0" > "$clampdev"
                i="$x"
        fi
        echo "Trying $i threads of load."
        ./load_m.sh "$runtime" "$i"

        ./energy.sh "$runtime" > "$energy_file$x.tmp"

        #this is for debug - to see which frequency was set by system/CPU
        cpupower frequency-info | grep 'current CPU frequency' > "$frequency_file$x.tmp"

        sleep 20
done

#disable clamping
echo 0 > "$clampdev"
