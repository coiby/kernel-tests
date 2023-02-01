#!/bin/bash
eval "$(shellspec - -c) exit 1"

# the plugins source from /usr/share/restraint/plugins, so make sure the file is created as expected
ln -fs "${PWD}/cki/restraint/plugins/cki_helpers" /usr/share/restraint/plugins/cki_helpers

Include /usr/share/restraint/plugins/cki_helpers

export LAB_CONTROLLER="beaker.test.com"
export RSTRNT_RECIPEID="54321"
export RSTRNT_TASKID="12345"

Mock rstrnt_info
    echo "rstrnt_info $*"
End

Mock dmesg
    echo "dmesg $*"
End

Mock curl
    echo "curl $*"
End

Mock sleep
    echo "sleep $*"
End

Mock diff
    echo "diff $*"
End

Describe 'cki-restraint: plugins'
    cleanup(){
        rm -rf "${CURRENT_TASK_PATH}"
    }
    BeforeEach 'cleanup'
    AfterEach 'cleanup'

    It "can run 26_cki_environment"
        When run script cki/restraint/plugins/task_run.d/26_cki_environment
        The first line should equal "rstrnt_info *** Running Plugin: cki/restraint/plugins/task_run.d/26_cki_environment"
        The file "${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/bootinfo" should be exist
        The status should be success
    End

    It "can run 30_init_test_console_log"
        When run script cki/restraint/plugins/task_run.d/30_init_test_console_log
        The first line should equal "dmesg -C"
        The stdout should include "curl --silent --show-error --retry 5 http://${LAB_CONTROLLER}:8000/recipes/${RSTRNT_RECIPEID}/logs/console.log -o ${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/init_console.log"
        The status should be success
    End

    It "can run 80_finish_console_log"
        mkdir -p "${CURRENT_TASK_PATH}/${RSTRNT_TASKID}"
        touch "${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/init_console.log"
        touch "${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/end_console.log"
        When run script cki/restraint/plugins/completed.d/80_finish_console_log
        The first line should equal "sleep 15"
        The line 2 should equal "curl --silent --show-error --retry 5 http://${LAB_CONTROLLER}:8000/recipes/${RSTRNT_RECIPEID}/logs/console.log -o ${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/end_console.log"
        The line 3 should equal "rstrnt-report-log -l ${CURRENT_TASK_PATH}/${RSTRNT_TASKID}/test_console.log"
        The status should be success
    End

    It "can run 90_cleanup_cki"
        When run script cki/restraint/plugins/completed.d/90_cleanup_cki
        The first line should equal "rstrnt_info *** Running Plugin: cki/restraint/plugins/completed.d/90_cleanup_cki"
        The status should be success
    End
End
