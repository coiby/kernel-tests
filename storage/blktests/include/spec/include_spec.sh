#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/include/include.sh

Describe 'blktests/include: do_test'
    setup() {
        # Mock the check script from blktests
        echo "echo running ./check \$@" > ./check
        chmod +x ./check
    }
    cleanup() {
        rm -rf ./check
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'

    cd(){
        echo "cd $*"
    }

    It "can pass do_test"
        When call do_test blktests test1

        The line 1 should include "Start to run test case blktests/tests/test1"
        The line 2 should equal "cd blktests"
        The line 3 should equal "running ./check test1"
        The line 4 should include "End blktests/tests/test1"
        The contents of file "${OUTPUTFILE}" should equal "running ./check test1"
        The status should be success
    End
End

Describe 'blktests/include: get_test_result'
    setup() {
        mkdir -p blktests/results
    }
    cleanup() {
        rm -rf blktests
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'

    It "can report pass"
        # To make sure we select the correct test
        echo "status fail" > blktests/results/test1
        echo "status pass" > blktests/results/test11
        echo "status fail" > blktests/results/test111

        When call get_test_result blktests test11
        The line 1 of output should equal "PASS"
        The lines of output should equal 1
        The status should be success
    End

    It "can report fail"
        # Best way I found to make sure the function was called with expected parameters
        Mock cki_upload_log_file
            echo "$*" >>  blktests/cki_upload_log_file.txt
        End
        # To make sure we select the correct test
        echo "status pass" > blktests/results/test1
        echo "status fail" > blktests/results/test11
        echo "status pass" > blktests/results/test111
        touch blktests/results/test11.out.bad.log
        touch blktests/results/test11.full.log
        touch blktests/results/test11.dmesg.log

        When call get_test_result blktests test11
        The line 1 should equal "FAIL"
        The status should be success
        The contents line 1 of file "blktests/cki_upload_log_file.txt" should equal "blktests/results/test11.out.bad.log"
        The contents line 2 of file "blktests/cki_upload_log_file.txt" should equal "blktests/results/test11.full.log"
        The contents line 3 of file "blktests/cki_upload_log_file.txt" should equal "blktests/results/test11.dmesg.log"
        The contents lines of file "blktests/cki_upload_log_file.txt" should equal 3
    End

    It "can report skip"
        # To make sure we select the correct test
        echo "status fail" > blktests/results/test1
        echo "status not run" > blktests/results/test11
        echo "status fail" > blktests/results/test111

        When call get_test_result blktests test11
        The line 1 of output should equal "SKIP"
        The lines of output should equal 1
        The status should be success
    End

    It "can report other"
        # To make sure we select the correct test
        echo "status fail" > blktests/results/test1
        echo "status invalid" > blktests/results/test11
        echo "status fail" > blktests/results/test111

        When call get_test_result blktests test11
        The line 1 of output should equal "OTHER"
        The lines of output should equal 1
        The status should be success
    End

    It "can report untested"
        # To make sure we select the correct test
        echo "status fail" > blktests/results/test1
        echo "status fail" > blktests/results/test111

        When call get_test_result blktests test11
        The line 1 of output should equal "UNTESTED"
        The lines of output should equal 1
    End
End
