#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

dmesg_check ()
{
    dmesg_dir="$1"
    if [ -z "$dmesg_dir" ]; then
        echo "FAIL: dmesg_check it looks like LTP run without saving dmesg for test cases"
        return
    fi

    # based on restraint dmesg check
    # https://github.com/restraint-harness/restraint/blob/master/plugins/report_result.d/01_dmesg_check
    LTP_FALSESTRINGS=${LTP_FALSESTRINGS:-"BIOS BUG|DEBUG|mapping multiple BARs.*IBM System X3250 M4"}
    LTP_FAILURESTRINGS=${LTP_FAILURESTRINGS:-"Oops|BUG|NMI appears to be stuck|Badness at"}

    debug "Checking for dmesg logs at $dmesg_dir"
    pushd "$LTPDIR"/output/"$dmesg_dir"
    for log in *.dmesg.log; do
        debug "Checking for issues on dmesg file $log"
        if grep -E -v "$LTP_FALSESTRINGS" "$log" | grep -Ew "$LTP_FAILURESTRINGS" >/dev/null 2>&1; then
            # report failed result dmesg check as subtest name dmesg_check_$subtestname
            subtestname=${log%.dmesg.log}
            rstrnt-report-result -o "$log" "dmesg_check_${subtestname}" FAIL
        fi
    done
    popd
}

report_result ()
{
    TEST=$1
    result=$2

    logfile_run=$OUTPUTDIR/$TEST.run.log
    logfile_fail=$OUTPUTDIR/$TEST.fail.log
    logfile_html=$OUTPUTDIR/$TEST.html
    logfile_json=$OUTPUTDIR/$TEST.json

    if [[ -z ${LTP_DMESG_DIR_PREFIX} ]]; then
        dmesg_dir=""
    else
        # get the most recent directory created
        # shellcheck disable=SC2010
        dmesg_dir=$(ls -t "$LTPDIR"/output/ | grep "${LTP_DMESG_DIR_PREFIX}" | head -1)
    fi

    # Always upload parsed test log for those failed test cases
    # get_failure_log $logfile_run "None" > $logfile_fail
    [ -s $logfile_fail ] && SubmitLog $logfile_fail
    # remove the '__with_dmesg_entry' from the test files
    # shellcheck disable=SC2045
    for testcase in $(ls *__with_dmesg_entry.* 2>/dev/null); do
        mv "$testcase" "${testcase//__with_dmesg_entry}"
    done
    # shellcheck disable=SC2010
    failed_tests=$(ls *.fail.log)
    for failed_test in $failed_tests; do
        # skip logfile_fail as it is not a test case fail log
        if [ "$failed_test" == "$logfile_fail" ]; then
            continue
        fi
        testcase_name="${failed_test%.fail.log}"
        # upload the failed test output as part of restraint subtest
        # extract test case name from test case fail log
        rstrnt-report-result -o "$failed_test" "${testcase_name}" FAIL
        # upload dmesg log for failed subtests
        SubmitLog "$LTPDIR"/output/"$dmesg_dir"/"${testcase_name}.dmesg.log"
    done

    dmesg_check "$dmesg_dir"

    # each failure is reported as subtest, always report pass for the summary result
    SUMMARY_RESULT=PASS
    # in case result is FAIL, but for some reason there is no subtest fail log
    # like there is no python3 for get_failure_log to parse the failures
    # make sure the summary has fail status, to make sure the test will have failed status
    if [[ -z "${failed_tests}" && "${result}" != "PASS" ]]; then
        SUMMARY_RESULT=FAIL
    fi
    # I want to see the succeeded running log as well
    SubmitLog $logfile_run
    SubmitLog $logfile_html
    SubmitLog $logfile_json
    score=$(cat $OUTPUTDIR/$RUNTEST.log | grep "failed" | awk '{print $2}')
    if test -f "$KIRK_DEBUG" && grep -E "Testing suite timed out: $RUNTEST" $KIRK_DEBUG; then
        echo "Some of the tests are not run. Please extend suite-timeout."
        rstrnt-report-result ${TEST}_suite_timeout WARN
    fi
    rstrnt-report-result "Summary ($TEST)" $SUMMARY_RESULT $score
}

SubmitLog ()
{
    LOG=$1

    rstrnt-report-log -l $LOG
}

CleanUp ()
{
    LOGFILE=$1

    if [ -e $OUTPUTDIR/$LOGFILE.run.log ]; then
        rm -f $OUTPUTDIR/$LOGFILE.run.log
    fi

    if [ -e $OUTPUTDIR/$LOGFILE.log ]; then
        rm -f $OUTPUTDIR/$LOGFILE.log
    fi
}

# Modify the $RUNTEST.log for eassier identifying KnownIssue case
log_deceiver ()
{
    if ! [ -f ${LTPDIR}/KNOWNISSUE ]; then
        return
    fi

    for k in $(cat ${LTPDIR}/KNOWNISSUE | grep -v '^#'); do
        sed -i '/'$k'/ s/FAIL/KNOW/' $OUTPUTDIR/$RUNTEST.log
    done
}

skip_testcase ()
{
    # skip tests defined in var SKIPTESTS, seperated by space
    if [ -n "$SKIPTESTS" ]; then
        echo -e ${SKIPTESTS// /"\n"} > ${LTPDIR}/SKIPTESTS
        # skip file needs to be an absolute path or path relative to $LTPROOT
        # use absolute path here
        OPTS="$OPTS --skip-file ${LTPDIR}/SKIPTESTS"
    fi
}

RunTest ()
{
    RUNTEST=$1
    OPTIONS=$2 # pass other options here, like "-b /dev/sda5 -B xfs"

    protect_harness_from_OOM

    # disable AVC check only in CGROUP tests
    if echo $RUNTEST | grep -q CGROUP; then
        export AVC_ERROR='+no_avc_check'
    fi

    check_time $RUNTEST

    # Default result to Fail
    export result_r="FAIL"

    # LTP will save the dmesg for each test in a directory with this prefix
    # under $LTPDIR/output
    LTP_DMESG_DIR_PREFIX="DMESG_DIR_$RUNTEST"

    ipc_debug_info Before
    debug "Command Line:"
    debug "kirk $RUNTEST $OUTPUTDIR \"$OPTIONS\""
    kirk_runltp $RUNTEST $OUTPUTDIR "$OPTIONS"

    ipc_debug_info After
    if [ $RUNTEST = "ipc" ]; then
        ipcrm_cleanup
        ipc_debug_info AfterIPCRMCleanup
    fi

    log_deceiver

    if ! [ -e $OUTPUTDIR/$RUNTEST.log ] || grep -q '\bfail\b' $OUTPUTDIR/$RUNTEST.log; then
        echo "$RUNTEST Failed: " | tee -a $OUTPUTFILE
        result_r="FAIL"
    else
        echo "$RUNTEST Passed: " | tee -a $OUTPUTFILE
        result_r="PASS"
    fi

    cat $OUTPUTDIR/$RUNTEST.log >> $OUTPUTFILE
    echo Test End Time: `date` >> $OUTPUTFILE

    # If REPORT_FAILED_RESULT set to "yes", report every failed test to beaker
    # so that it's easier to see which tests failed.
    if [[ "$REPORT_FAILED_RESULT" == "yes" && "$result_r" == "FAIL" ]]; then
        while read test res ret; do
            if [ "$res" != "FAIL" ]; then
                continue
            fi
            report_result $RUNTEST/$test $res $ret
        done < $OUTPUTDIR/$RUNTEST.log
    fi
    report_result $RUNTEST $result_r

    # Restore AVC check
    if echo $RUNTEST | grep -q CGROUP; then
        export AVC_ERROR=''
    fi
}

RunFiltTest ()
{
    if [ -n "$FILTERTESTS" ]; then
        rm -f $OUTPUTDIR/filtertests.log
        rm -f $OUTPUTDIR/filtertests.run.log

        echo "$FILTERTESTS" | tr ' ' '\n' | awk '{print $1, $1}' > $LTPDIR/runtest/filtertests

        RunTest filtertests "$OPTS"
        return 0
    fi

    return 1
}
