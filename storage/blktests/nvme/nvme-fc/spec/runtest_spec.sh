#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/nvme/nvme-fc/runtest.sh

Describe 'blktests - nvme-fc - main'
    Mock enable_nvme_core_multipath
        echo "enable_nvme_core_multipath"
    End

    Mock get_test_cases_fc
        echo "nvme/003"
    End

    Mock do_test
        echo "do_test $*"
        # the nvme_trtype env variable should be fc
        echo "nvme_trtype = ${nvme_trtype:?}"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main"
        When call main

        The line 1 should equal "enable_nvme_core_multipath"
        The line 2 should equal "do_test ./blktests nvme/003"
        The line 3 should equal "nvme_trtype = fc"
        The line 4 should equal "rstrnt-report-result nvme-fc: storage/blktests/nvme/nvme-fc/tests/nvme/003 PASS 0"
        The status should be success
    End
End

