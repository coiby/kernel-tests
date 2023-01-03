#!/bin/bash
eval "$(shellspec - -c) exit 1"

Describe 'reboot-test: pre-reboot'
    setup(){
        rm -f kernel_before_reboot.txt
    }
    BeforeEach 'setup'
    It "can reboot"
        When call bash misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info before reboot"
        The stdout should include "Reboot now!"
        The stdout should include "rstrnt-reboot"
        The status should be success
    End
End

Describe 'reboot-test: post-reboot'
    cleanup(){
        rm -f kernel_before_reboot.txt kernel_after_reboot.txt /tmp/journalctl.log
    }
    AfterAll 'cleanup'

    type(){
       return "${TYPE_EXIT_CODE:=0}"
    }
    export -f type

    Mock journalctl
        echo "${MOCKED_JOURNALCTL:-}"
        if [ "$#" -ne "2" ]; then
            echo 'FAIL: expected journalctl to be called with 2 parameters like: --since "2022-12-23 11:36:36"'
            exit 1
        fi
        regexp="^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"
        if ! echo "$2" | grep -qE "${regexp}"; then
            echo "FAIL: journalctl was called with invalid date parameter: $2"
            exit 0
        fi
    End
    Mock diff
        echo "diff $*"
        exit "${DIFF_EXIT_CODE:=0}"
    End

    It "can boot without errors when there is no journalctl"
        export TYPE_EXIT_CODE=1
        When call bash misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test PASS"
        The status should be success
    End

    It "can boot without errors"
        When call bash misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test PASS"
        The status should be success
    End

    It "can detect boot using wrong kernel"
        export DIFF_EXIT_CODE=1
        When call bash misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "FAIL: Rebooted using different kernel"
        The stdout should include "Before reboot:"
        The stdout should include "After reboot:"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check FAIL 0"
        The stdout should include "rstrnt-report-result misc/reboot-test/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test FAIL"
        The status should be failure
    End

    It "can detect Call Traces on journalctl"
        export MOCKED_JOURNALCTL="Call Trace:"
        When call bash misc/reboot-test/runtest.sh
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "FAIL: Call trace found in journalctl, see journalctl.log"
        The stdout should include "rstrnt-report-log -l /tmp/journalctl.log"
        The stdout should include "rstrnt-report-result misc/reboot-test/journalctl-check FAIL 0"
        The stdout should include "rstrnt-report-result misc/reboot-test FAIL"
        The contents of file /tmp/journalctl.log should include "${MOCKED_JOURNALCTL}"
        The status should be failure
    End
End
