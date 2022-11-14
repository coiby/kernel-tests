#!/bin/bash -x
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
perf_ofile="perf_test_output_"

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

for i in `./thread_numbers.py "$cores"`; do
        echo "Trying $i threads of load."
        ./load_m.sh "$runtime" "$i"
        echo "$i threads for $runtime s run:" >> "$perf_ofile$i.tmp"
        perf stat -a -e "power/energy-cores/" sleep "$runtime" 2> "$perf_ofile$i.tmp"
        perf_out="$?"

        echo "Perf reported $perf_out"
        if [ "$perf_out" != 0 ]; then
                echo "Perf failed for $i-threads load." >> "$warn_file"
        fi

        sleep 20
done

