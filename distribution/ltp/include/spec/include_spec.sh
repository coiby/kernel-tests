#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include distribution/ltp/include/runtest.sh

Describe "distribution/ltp/include: DmesgCheck"
    Mock DeBug
        echo "$*"
    End

    It "DmesgCheck - No failure"
        LTP_DMESG_DIR_PREFIX=mock_dir_TEST1
        dirname=${LTP_DMESG_DIR_PREFIX}_$(date +%X)
        mkdir -p "${LTPDIR}/output/${dirname}"
        touch "${LTPDIR}/output/${dirname}/subtest0.dmesg.log"
        echo "BIOS BUG" > \
            "${LTPDIR}/output/${dirname}/subtest1.dmesg.log"
        echo "DEBUG" > \
            "${LTPDIR}/output/${dirname}/subtest2.dmesg.log"
        echo "mapping multiple BARs.*IBM System X3250 M4" > \
            "${LTPDIR}/output/${dirname}/subtest3.dmesg.log"
        When call DmesgCheck TEST1
        The line 1 of stdout should equal "Checking for dmesg logs at ${dirname}"
        The line 2 of stdout should include "${LTPDIR}/output/${dirname}"
        The line 3 of stdout should equal "Checking for issues on dmesg file subtest0.dmesg.log"
        The line 4 of stdout should equal "Checking for issues on dmesg file subtest1.dmesg.log"
        The line 5 of stdout should equal "Checking for issues on dmesg file subtest2.dmesg.log"
        The line 6 of stdout should equal "Checking for issues on dmesg file subtest3.dmesg.log"
        The status should be success
        rm -rf "${LTPDIR}/output/"
    End

    It "DmesgCheck - With failure"
        LTP_DMESG_DIR_PREFIX=mock_dir_TEST1
        dirname=${LTP_DMESG_DIR_PREFIX}_$(date +%X)
        mkdir -p "${LTPDIR}/output/${dirname}"
        touch "${LTPDIR}/output/${dirname}/subtest0.dmesg.log"
        echo "Oops " > \
            "${LTPDIR}/output/${dirname}/subtest1.dmesg.log"
        echo "watchdog: BUG: soft lockup - CPU#3 stuck for 22s!" > \
            "${LTPDIR}/output/${dirname}/subtest2.dmesg.log"
        echo "NMI appears to be stuck" > \
            "${LTPDIR}/output/${dirname}/subtest3.dmesg.log"
        echo "Badness at" > \
            "${LTPDIR}/output/${dirname}/subtest4.dmesg.log"
        When call DmesgCheck TEST1
        The line 1 of stdout should equal "Checking for dmesg logs at ${dirname}"
        The line 2 of stdout should include "${LTPDIR}/output/${dirname}"
        The line 3 of stdout should equal "Checking for issues on dmesg file subtest0.dmesg.log"
        The line 4 of stdout should equal "Checking for issues on dmesg file subtest1.dmesg.log"
        The line 5 of stdout should equal "rstrnt-report-result -o subtest1.dmesg.log dmesg_check_subtest1 FAIL"
        The line 6 of stdout should equal "Checking for issues on dmesg file subtest2.dmesg.log"
        The line 7 of stdout should equal "rstrnt-report-result -o subtest2.dmesg.log dmesg_check_subtest2 FAIL"
        The line 8 of stdout should equal "Checking for issues on dmesg file subtest3.dmesg.log"
        The line 9 of stdout should equal "rstrnt-report-result -o subtest3.dmesg.log dmesg_check_subtest3 FAIL"
        The line 10 of stdout should equal "Checking for issues on dmesg file subtest4.dmesg.log"
        The line 11 of stdout should equal "rstrnt-report-result -o subtest4.dmesg.log dmesg_check_subtest4 FAIL"
        The status should be success
        rm -rf "${LTPDIR}/output/"
    End

    It "DmesgCheck - missing dmesg dir prefix"
        When call DmesgCheck TEST1
        The line 1 of stdout should equal "FAIL: DmesgCheck requires LTP_DMESG_DIR_PREFIX to be set"
        The status should be success
    End
End

Describe "distribution/ltp/include: RprtRslt"
    cleanup() {
        rm -rf *.fail.log
    }
    AfterEach 'cleanup'
    Mock cat
        echo "${CAT_OUTPUT}"
    End

    Mock GetFailureLog
        echo "GetFailureLog $*"
    End

    Mock DmesgCheck
        echo "DmesgCheck $*"
    End

    Parameters
        # results - subtest failed log - total failures
        PASS "" "0"
        FAIL "prctl09.fail.log" "1"
        FAIL "" "1"
    End
    It "RprtRslt $1 $2"
        # Mock the failed test log
        if [[ -n $2 ]]; then
            touch $2
        fi
        export CAT_OUTPUT="Total Failures: ${3}"
        RESULT="${1}"
        SCORE=${3}
        When call RprtRslt TEST1 "${RESULT}"
        The first line of stdout should include "rstrnt-report-log -l /mnt/testarea/TEST1.fail.log"
        if [[ -n "${LS_OUTPUT}" ]]; then
            The stdout should include "rstrnt-report-result -o prctl09.fail.log prctl09 FAIL"
        fi
        The stdout should include "DmesgCheck TEST1"
        SUMMARY_RESULT=PASS
        # in case result is FAIL, but for some reason there is no subtest fail log
        # make sure the summary has fail status, to make sure the test will have failed status
        if [[ -z "${LS_OUTPUT}" && "${RESULT}" != "PASS" ]]; then
            SUMMARY_RESULT=FAIL
        fi
        The stdout should include "rstrnt-report-result Summary (TEST1) ${SUMMARY_RESULT} ${SCORE}"
        The status should be success
    End
End
