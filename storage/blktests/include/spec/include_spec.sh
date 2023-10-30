#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/blktests/include/include.sh

Describe 'blktests - include'
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

