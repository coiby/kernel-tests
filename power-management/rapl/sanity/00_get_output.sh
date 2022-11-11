#!/bin/bash
# Prepares data (output of turbostat and perf) for next tests. Runs for defined time
# with or without load.
#
# $1 = runtime
# $2 = load

# Author:  Erik Hamera alias lhc
# contact: lhc (at) redhat (dot) com
#          ehamera (at) redhat (dot) com
# License: GNU GPL

# hardcoded files for data output
turbostat_ofile="turbostat_test_output.tmp"
perf_ofile="perf_test_output.tmp"
# hardcoded file for all warnings - the script will end with 0 (PASS) in case of warning
# warnings are handled at the end of testcase
warn_file="warn.tmp"


if [ -n "$1" ]; then
        runtime="$1"
else
        runtime="300"
fi

## here can be some load
if [ -n "$2" ]; then
        $2 "$runtime" &
fi


perf stat -a -e "power/energy-cores/" sleep "$runtime" 2> "$perf_ofile" &
perf_pid="$!"
turbostat sleep "$runtime" 2> "$turbostat_ofile" &
turbostat_pid="$!"

wait "$perf_pid"
perf_out="$?"
wait "$turbostat_pid"
turbostat_out="$?"


if grep "invalid or unsupported event: 'power/energy-cores/'" "$perf_ofile" /dev/null; then
        echo 'perf: invalid or unsupported event: power/energy-cores/' >> "$warn_file"
        exit 0
fi


echo "perf returned: $perf_out, turbostat returned: $turbostat_out"

if [ "$perf_out" != 0 ]; then
        echo 'perf' >> "$warn_file"
fi
if [ "$turbostat_out" != 0 ]; then
        echo 'turbostat' >> "$warn_file"
fi

#warnings are handled at the end from $warn_file file
exit 0
