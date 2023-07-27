#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include distribution/ltp/include/runtest.sh

Describe "distribution/ltp/include: RprtRslt"
    Mock cat
        echo "${CAT_OUTPUT}"
    End

    Mock GetFailureLog
        echo "GetFailureLog $*"
    End

    Mock ls
        echo "${LS_OUTPUT}"
    End

    Parameters
        # results - subtest failed log - total failures
        PASS "" "0"
        FAIL "prctl09.fail.log" "1"
        FAIL "" "1"
    End
    It "RprtRslt $1 $2"
        export LS_OUTPUT="${2}"
        export CAT_OUTPUT="Total Failures: ${3}"
        RESULT="${1}"
        SCORE=${3}
        When call RprtRslt TEST1 "${RESULT}"
        The first line of stdout should include "rstrnt-report-log -l /mnt/testarea/TEST1.fail.log"
        if [[ -n "${LS_OUTPUT}" ]]; then
            The stdout should include "rstrnt-report-result -o prctl09.fail.log prctl09 FAIL"
        fi
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
