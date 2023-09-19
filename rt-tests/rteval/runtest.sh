#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../include/runtest.sh || exit 1

export TEST="rt-tests/rteval"

# User Parameters
: "${DURATION:=900}"
: "${LATCHECK:=1}"
: "${MAXLAT:=150}"
: "${STDDEVLAT:=5}"

function RprtRslt ()
{
    declare result=$1

    # File the results in the database
    if [ $result = "PASS" ]; then
        rstrnt-report-result $TEST $result 0
    else
        rstrnt-report-result $TEST $result 1
    fi
}

function MeasureLatency()
{
    which bc >/dev/null || yum install -y bc

    # Verify the max and stddev latency fall within tolerable range
    declare max_lat stddev_lat
    max_lat=$(grep -A 11 'System:' $OUTPUTFILE | \
              grep 'Max:' | awk -F ':' '{print $2}' | xargs)
    stddev_lat=$(grep -A 11 'System:' $OUTPUTFILE | \
                 grep 'Std.dev:' | awk -F ':' '{print $2}' | xargs)

    echo "rteval max/stddev lat was: ${max_lat} / ${stddev_lat}" | \
        tee -a $OUTPUTFILE

    if ! (( $(echo "${max_lat%us} < $MAXLAT" | bc -l) )); then
        echo "FAIL: maximum latency of $max_lat exceeds ${MAXLAT}us" | \
            tee -a $OUTPUTFILE
        result_r="FAIL"
    fi

    if ! (( $(echo "${stddev_lat%us} < $STDDEVLAT" | bc -l) )); then
        echo "FAIL: std.dev latency of $stddev_lat exceeds ${STDDEVLAT}us" | \
            tee -a $OUTPUTFILE
        result_r="FAIL"
    fi
}

function RunTest ()
{
    # Default result to Fail
    export result_r="FAIL"

    echo "Test Start Time: $(date)" | tee -a $OUTPUTFILE

    echo "-- INFO -- Default run time: $DURATION seconds" | tee -a $OUTPUTFILE

    echo "-- INFO -- Mounting debugfs to/sys/kernel/debug" | tee -a $OUTPUTFILE
    mount -t debugfs none /sys/kernel/debug

    echo "-- INFO -- Using command line: rteval --duration=$DURATION" | \
        tee -a $OUTPUTFILE

    # Lets rock'n'roll
    rteval --duration=$DURATION -D -L | tee -a $OUTPUTFILE
    retcode="${PIPESTATUS[0]}"

    find . -maxdepth 1 -name "rteval-????????-*.tar.bz2" -print |
        while IFS= read -r rep; do
            echo "-- INFO -- Attaching report: $rep" | tee -a $OUTPUTFILE
            rstrnt-report-log -l $rep
        done

    if [ ${retcode} -eq 0 ] ; then
        echo "rteval Passed: " | tee -a $OUTPUTFILE
        result_r="PASS"
        [ $LATCHECK -eq 1 ] && MeasureLatency
    else
        echo "rteval Failed: " | tee -a $OUTPUTFILE
        result_r="FAIL"
    fi

    echo "Test End Time: $(date)" | tee -a $OUTPUTFILE
    RprtRslt $result_r
}

# ---------- Start Test -------------
if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    rt_env_setup
    ! cki_is_kernel_automotive && enable_tuned_realtime
fi
RunTest
exit 0
