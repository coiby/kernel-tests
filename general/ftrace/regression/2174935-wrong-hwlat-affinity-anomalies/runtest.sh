#!/bin/bash

TEST="2174935-wrong-hwlat-affinity-anomalies"
TRACE_PATH=/sys/kernel/tracing

if ! mount -l | grep 'tracefs'; then
    echo "tracefs are not mount"
    rstrnt-report-result "tracefs-mount" "FAIL" 1
    exit 1
fi

# start
pushd $TRACE_PATH || {
    echo "No directory $TRACE_PATH"
    rstrnt-report-result "tracing-not-exist" "FAIL" 1
    exit 1
}
unshare --fork --pid bash -c 'echo hwlat > current_tracer;echo round-robin > hwlat_detector/mode;echo 1 > tracing_on;'; dmesg -c
cat hwlat_detector/mode
if grep '\[round-robin\]' hwlat_detector/mode; then
    echo "PASS, cpumask didn't switching the round-robin mode."
    rstrnt-report-result "$TEST" "PASS" 0
else
    echo "FAIL, hwlat_detector: cpumask changed while in round-robin mode, switching to mode non"
    rstrnt-report-result "$TEST" "FAIL" 1
fi
popd || exit

exit 0
