#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/nvme/nvme-rdma/runtest.sh

Describe 'blktests - nvme-rdma - main'
    Mock enable_nvme_core_multipath
        echo "enable_nvme_core_multipath"
    End

    Mock get_test_cases_rdma
        echo "nvme/001"
    End

    Mock do_test
        echo "do_test $*"
        # the nvme_trtype env variable set by the test
        echo "nvme_trtype = ${nvme_trtype:?}"
        # the use_siw env variable set by the test
        echo "use_siw = ${use_siw:-}"
    End

    Mock get_test_result
        echo "PASS"
    End

    It "can pass main"
        When call main

        The line 1 should equal "enable_nvme_core_multipath"
        The line 2 should equal "do_test ./blktests nvme/001"
        The line 3 should equal "nvme_trtype = rdma"
        The line 4 should equal "use_siw = "
        The line 5 should equal "rstrnt-report-result  nvme-rdma: storage/blktests/nvme/nvme-rdma/tests/nvme/001 PASS 0"
        The line 6 should equal "do_test ./blktests nvme/001"
        The line 7 should equal "nvme_trtype = rdma"
        The line 8 should equal "use_siw = 1"
        The line 9 should equal "rstrnt-report-result use_siw=1 nvme-rdma: storage/blktests/nvme/nvme-rdma/tests/nvme/001 PASS 0"
        The status should be success
    End
End

