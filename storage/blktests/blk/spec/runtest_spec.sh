#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/blk/runtest.sh

Describe 'blktests - blk - main'
    Mock rlIsRHEL
        if [[ "$1" == "${_RHEL_VER}" ]]; then
            exit 0
        fi
        exit 1
    End

    Mock rlIsFedora
        exit 1
    End

    Mock rlIsCentOS
        exit 1
    End

    Mock get_test_cases_block
        echo "block/001"
    End

    Mock get_test_cases_loop
        echo "loop/001"
    End

    Mock get_test_cases_nvme
        echo "nvme/001"
    End

    Mock get_test_cases_scsi
        echo "scsi/001"
    End

    Mock get_test_cases_zbd
        echo "zbd/001"
    End

    Mock do_test
        echo "do_test $*"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main - RHEL 7"
        export _RHEL_VER=7
        When call main

        The line 1 should equal "do_test ./blktests block/001"
        The line 2 should equal "rstrnt-report-result storage/blktests/tests/block/001 PASS 0"
        The line 3 should equal "do_test ./blktests loop/001"
        The line 4 should equal "rstrnt-report-result storage/blktests/tests/loop/001 PASS 0"
        The status should be success
    End

    It "can pass main - RHEL 8"
        export _RHEL_VER=8
        When call main

        The line 1 should equal "do_test ./blktests block/001"
        The line 2 should equal "rstrnt-report-result storage/blktests/tests/block/001 PASS 0"
        The line 3 should equal "do_test ./blktests loop/001"
        The line 4 should equal "rstrnt-report-result storage/blktests/tests/loop/001 PASS 0"
        The line 5 should equal "do_test ./blktests nvme/001"
        The line 6 should equal "rstrnt-report-result storage/blktests/tests/nvme/001 PASS 0"
        The line 7 should equal "do_test ./blktests scsi/001"
        The line 8 should equal "rstrnt-report-result storage/blktests/tests/scsi/001 PASS 0"
        The status should be success
    End

    It "can pass main - RHEL 9"
        export _RHEL_VER=9
        When call main

        The line 1 should equal "do_test ./blktests block/001"
        The line 2 should equal "rstrnt-report-result storage/blktests/tests/block/001 PASS 0"
        The line 3 should equal "do_test ./blktests loop/001"
        The line 4 should equal "rstrnt-report-result storage/blktests/tests/loop/001 PASS 0"
        The line 5 should equal "do_test ./blktests nvme/001"
        The line 6 should equal "rstrnt-report-result storage/blktests/tests/nvme/001 PASS 0"
        The line 7 should equal "do_test ./blktests scsi/001"
        The line 8 should equal "rstrnt-report-result storage/blktests/tests/scsi/001 PASS 0"
        The line 9 should equal "do_test ./blktests zbd/001"
        The line 10 should equal "rstrnt-report-result storage/blktests/tests/zbd/001 PASS 0"
        The status should be success
    End
End

