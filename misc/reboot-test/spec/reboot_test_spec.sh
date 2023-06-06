#!/bin/bash
eval "$(shellspec - -c) exit 1"

type(){
    return "${TYPE_EXIT_CODE:=0}"
}
export -f type

Mock journalctl
    echo "journalctl $*"
    echo "${JOURNAL_OUTPUT:=}"
End

Describe 'reboot-test: pre-reboot'
    setup(){
        rm -f kernel_before_reboot.txt
    }
    BeforeEach 'setup'
    It "can reboot"
        When run script misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info before reboot"
        The stdout should include "Reboot now!"
        The stdout should include "rstrnt-reboot"
        The status should be success
    End
End

Describe 'reboot-test: post-reboot'
    cleanup(){
        rm -f kernel_before_reboot.txt kernel_after_reboot.txt
        rm -f journalctl_before_reboot.log journalctl_after_reboot.log journalctl.log
    }
    AfterAll 'cleanup'

    Mock diff
        echo "diff $*"
        echo "${DIFF_OUTPUT:=}"
        exit "${DIFF_EXIT_CODE:=0}"
    End

    It "can boot without errors when there is no journalctl"
        export TYPE_EXIT_CODE=1
        When run script misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test PASS"
        The status should be success
    End

    It "can boot without errors"
        When run script misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "rstrnt-report-result -o journalctl.log misc/reboot-test/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test PASS"
        The status should be success
    End

    It "can detect boot using wrong kernel"
        export DIFF_EXIT_CODE=1
        When run script misc/reboot-test/runtest.sh
        The first line should equal "Saving kernel info after reboot"
        The stdout should include "FAIL: Rebooted using different kernel"
        The stdout should include "Before reboot:"
        The stdout should include "After reboot:"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check FAIL 0"
        The stdout should include "rstrnt-report-result -o journalctl.log misc/reboot-test/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result misc/reboot-test FAIL"
        The status should be failure
    End

    It "can detect Call Traces on journalctl"
        export JOURNAL_OUTPUT="Call Trace:"
        When run script misc/reboot-test/runtest.sh
        The stdout should include "diff kernel_before_reboot.txt kernel_after_reboot.txt"
        The stdout should include "Rebooted using correct kernel"
        The stdout should include "rstrnt-report-result misc/reboot-test/kernel-version-check PASS 0"
        The stdout should include "FAIL: Call trace found in journalctl, see journalctl.log"
        #The stdout should include "rstrnt-report-log -l journalctl.log"
        The stdout should include "rstrnt-report-result -o journalctl.log misc/reboot-test/journalctl-check FAIL 0"
        The stdout should include "rstrnt-report-result misc/reboot-test FAIL"
        The contents of file journalctl.log should include "${MOCKED_JOURNALCTL}"
        The status should be failure
    End
End
