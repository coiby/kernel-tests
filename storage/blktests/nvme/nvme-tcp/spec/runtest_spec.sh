#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/nvme/nvme-tcp/runtest.sh

Describe 'blktests - nvme-tcp - main'
    Mock enable_nvme_core_multipath
        echo "enable_nvme_core_multipath"
    End

    Mock get_test_cases_tcp
        echo "nvme/001"
    End

    Mock do_test
        echo "do_test $*"
        # the nvme_trtype env variable set by the test
        echo "nvme_trtype = ${nvme_trtype:?}"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main"
        When call main

        The line 1 should equal "enable_nvme_core_multipath"
        The line 2 should equal "do_test ./blktests nvme/001"
        The line 3 should equal "nvme_trtype = tcp"
        The line 4 should equal "rstrnt-report-result nvme-tcp: storage/blktests/nvme/nvme-tcp/tests/nvme/001 PASS 0"
        The status should be success
    End
End

