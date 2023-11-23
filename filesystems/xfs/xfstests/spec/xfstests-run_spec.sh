#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include filesystems/xfs/xfstests/xfstests-run.sh

Describe 'filesystems/xfs/xfstests/xfstests-run: check_tests'
    setup(){
        rm -rf results
        mkdir results
    }
    cleanup(){
        rm -rf tests
        rm -rf results
        rm check
    }
    BeforeEach 'setup'
    AfterAll 'cleanup'

    #mock these function from misc.sh to avoid including this file
    Mock echoo
        echo "$*"
    End
    Mock xlog
        "$@"
    End

    Mock dmesg
        echo "dmesg $*"
    End
    export RUNTESTS="generic/test1 generic/test2"

    # Mock check script
    echo "echo $*" > check
    # mock the test cases
    [[ -d tests/generic ]] || mkdir -p tests/generic
    touch tests/generic/test1
    touch tests/generic/test2
    chmod +x check

    It "can report pass"
        When call check_tests
        The line 1 should equal "Running test generic/test1"
        The line 3 should equal "Running test generic/test2"
        The status should be success
    End

    It "can report pass with REPORT_PASS"
        export REPORT_PASS=1
        echo "generic/test1 5s" > results/check.time
        echo "generic/test2 1s" >> results/check.time
        When call check_tests
        The line 1 should equal "Running test generic/test1"
        The line 3 should equal "rstrnt-report-result generic/test1 PASS 5s"
        The line 4 should equal "Running test generic/test2"
        The line 6 should equal "rstrnt-report-result generic/test2 PASS 1s"
        The status should be success
    End

    It "can report fail"
        # Mock check script
        echo "echo $* && exit 1" > check
        Mock cp
            echo "cp $*"
        End
        Mock release_loops
            echo "release_loop"s
        End
        mkdir results/generic
        echo "" > results/generic/generic-test1.dmesg.log
        echo "" > results/generic/generic-test2.dmesg.log
        When call check_tests
        The line 1 should equal "Running test generic/test1"
        The line 3 should equal "rstrnt-report-log -l results/generic/generic-test1.log"
        The line 4 should equal "cp results/generic/test1.dmesg.log results/generic/generic-test1.dmesg.log"
        The line 5 should equal "rstrnt-report-log -l results/generic/generic-test1.dmesg.log"
        The line 6 should equal "rstrnt-report-result generic/test1 FAIL 0"
        The line 7 should equal "release_loops"
        The line 8 should equal "Running test generic/test2"
        The line 10 should equal "rstrnt-report-log -l results/generic/generic-test2.log"
        The line 11 should equal "cp results/generic/test2.dmesg.log results/generic/generic-test2.dmesg.log"
        The line 12 should equal "rstrnt-report-log -l results/generic/generic-test2.dmesg.log"
        The line 13 should equal "rstrnt-report-result generic/test2 FAIL 0"
        The line 14 should equal "release_loops"
        The status should be success
    End

    It "doesn't report fail for false alarm"
        __end__() {
            %preserve false_alarm
        }
        # logs are uploaded, but no result is reported in this case
        # Mock check script
        echo "echo $* && exit 1" > check
        Mock cp
            echo "cp $*"
        End
        Mock release_loops
            echo "release_loop"s
        End
        mkdir results/generic
        echo "" > results/generic/generic-test1.dmesg.log
        echo "possible circular locking dependency detected" > results/generic/generic-test2.dmesg.log
        When call check_tests
        The line 1 should equal "Running test generic/test1"
        The line 3 should equal "rstrnt-report-log -l results/generic/generic-test1.log"
        The line 4 should equal "cp results/generic/test1.dmesg.log results/generic/generic-test1.dmesg.log"
        The line 5 should equal "rstrnt-report-log -l results/generic/generic-test1.dmesg.log"
        The line 6 should equal "rstrnt-report-result generic/test1 FAIL 0"
        The line 7 should equal "release_loops"
        The line 8 should equal "Running test generic/test2"
        The line 10 should equal "rstrnt-report-log -l results/generic/generic-test2.log"
        The line 11 should equal "cp results/generic/test2.dmesg.log results/generic/generic-test2.dmesg.log"
        The line 12 should equal "rstrnt-report-log -l results/generic/generic-test2.dmesg.log"
        The line 13 should equal "possible circular locking dependency detected"
        The line 14 should equal "release_loops"
        The variable false_alarm should equal "1"
    End
End
