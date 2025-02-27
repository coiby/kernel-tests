#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include distribution/ltp/include-ng/run.sh

Describe "distribution/ltp/include-ng: dmesg_check"
    Mock debug
        echo "$*"
    End

    It "dmesg_check - No failure"
        dirname=mock_dir_TEST1_$(date +%X)
        mkdir -p "${LTPDIR}/output/${dirname}"
        touch "${LTPDIR}/output/${dirname}/subtest0.dmesg.log"
        echo "BIOS BUG" > \
            "${LTPDIR}/output/${dirname}/subtest1.dmesg.log"
        echo "DEBUG" > \
            "${LTPDIR}/output/${dirname}/subtest2.dmesg.log"
        echo "mapping multiple BARs.*IBM System X3250 M4" > \
            "${LTPDIR}/output/${dirname}/subtest3.dmesg.log"
        When call dmesg_check "$dirname"
        The line 1 of stdout should equal "Checking for dmesg logs at ${dirname}"
        The line 2 of stdout should include "${LTPDIR}/output/${dirname}"
        The line 3 of stdout should equal "Checking for issues on dmesg file subtest0.dmesg.log"
        The line 4 of stdout should equal "Checking for issues on dmesg file subtest1.dmesg.log"
        The line 5 of stdout should equal "Checking for issues on dmesg file subtest2.dmesg.log"
        The line 6 of stdout should equal "Checking for issues on dmesg file subtest3.dmesg.log"
        The status should be success
        rm -rf "${LTPDIR}/output/"
    End

    It "dmesg_check - With failure"
        dirname=mock_dir_TEST1_$(date +%X)
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
        When call dmesg_check "$dirname"
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

    It "dmesg_check - missing dmesg dir prefix"
        When call dmesg_check
        The line 1 of stdout should equal "FAIL: dmesg_check it looks like LTP run without saving dmesg for test cases"
        The status should be success
    End
End
