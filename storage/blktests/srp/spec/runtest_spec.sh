#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/srp/runtest.sh

Describe 'blktests - srp - main'
    Mock pre_setup
        echo "pre_setup"
    End

    Mock disable_multipath
        echo "disable_multipath"
    End

    Mock get_test_cases_list SRP_RXE
        echo "srp/001"
    End

    Mock do_test
        echo "do_test $*"
        # the use_rxe env variable set by the test
        echo "use_rxe = ${use_rxe:-}"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main"
        When call main

        The line 1 should equal "pre_setup"
        The line 2 should equal "disable_multipath"
        The line 3 should equal "do_test ${CDIR}/blktests srp/001"
        The line 4 should equal "use_rxe = 1"
        The line 5 should equal "rstrnt-report-result use_rxe=1 srp: storage/blktests/srp/tests/srp/001 PASS 0"
        The line 6 should equal "do_test ${CDIR}/blktests srp/001"
        The line 7 should equal "use_rxe = "
        The line 8 should equal "rstrnt-report-result  srp: storage/blktests/srp/tests/srp/001 PASS 0"
        The status should be success
    End
End

