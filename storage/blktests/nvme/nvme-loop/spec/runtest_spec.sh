#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/nvme/nvme-loop/runtest.sh

Describe 'blktests - nvme-loop - main'
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

    Mock enable_nvme_core_multipath
        echo "enable_nvme_core_multipath"
    End

    Mock get_test_cases_list
        echo "nvme/003"
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
        The line 2 should equal "do_test ${CDIR}/blktests nvme/003"
        The line 3 should equal "nvme_trtype = loop"
        The line 4 should equal "rstrnt-report-result nvme-loop: storage/blktests/nvme/nvme-loop/tests/nvme/003 PASS 0"
        The status should be success
    End
End

