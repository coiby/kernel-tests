#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/nvme/nvmeof-mp/runtest.sh

Describe 'blktests - nvmeof-mp - main'
    Mock pre_setup
        echo "pre_setup"
    End

    Mock get_test_cases
        echo "nvmeof-mp/005"
    End

    Mock do_test
        echo "do_test $*"
        # the use_siw env variable set by the test
        echo "use_siw = ${use_siw:-}"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main"
        When call main

        The line 1 should equal "pre_setup"
        The line 2 should equal "do_test ./blktests nvmeof-mp/005"
        The line 3 should equal "use_siw = "
        The line 4 should equal "rstrnt-report-result  nvmeof-mp: storage/blktests/nvme/nvmeof-mp/tests/nvmeof-mp/005 PASS 0"
        The line 5 should equal "do_test ./blktests nvmeof-mp/005"
        The line 6 should equal "use_siw = 1"
        The line 7 should equal "rstrnt-report-result use_siw=1 nvmeof-mp: storage/blktests/nvme/nvmeof-mp/tests/nvmeof-mp/005 PASS 0"
        The status should be success
    End
End

