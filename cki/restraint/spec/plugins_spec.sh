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

Describe 'cki-restraint: runtest.sh'
    Mock sed
        echo "sed $*"
    End
    Mock grep
        echo "grep $*"
    End
    Mock cp
        echo "cp $*"
    End
    Mock chmod
        echo "chmod $*"
    End
    It 'can run runtest.sh'
        When run script cki/restraint/runtest.sh
        The stdout should include "sed -i s|rstrnt-reboot|if [ \"\${CKI_ABORT_RECIPE_ON_LWD:-0}\" -eq \"1\" ]; then rstrnt-abort recipe; else rstrnt-report-result \"\${RSTRNT_TASKNAME}\" WARN\nexit 0\nrstrnt-reboot;fi| /usr/share/restraint/plugins/localwatchdog.d/99_reboot"
        The stdout should include 'cp -rf plugins /usr/share/restraint/'
        The stdout should include 'chmod -R +x /usr/share/restraint/plugins'
        # shellcheck disable=SC2016 # we don't wan't to expand the variable when writting to the file
        The stderr should include "sed -i 's|rstrnt-reboot|if [ \"\${CKI_ABORT_RECIPE_ON_LWD:-0}\" -eq \"1\" ]; then rstrnt-abort recipe; else rstrnt-report-result \"\${RSTRNT_TASKNAME}\" WARN\nexit 0\nrstrnt-reboot;fi|' /usr/share/restraint/plugins/localwatchdog.d/99_reboot"
        The status should be success
    End
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
        The file "${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/bootinfo" should be exist
        The status should be success
    End

    It "can run 30_init_test_console_log"
        When run script cki/restraint/plugins/task_run.d/30_init_test_console_log
        The stdout should include "curl --silent --show-error --retry 5 http://${LAB_CONTROLLER}:8000/recipes/${RSTRNT_RECIPEID}/logs/console.log -o ${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/init_console.log"
        The status should be success
    End

    It "can run 80_finish_console_log"
        mkdir -p "${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}"
        touch "${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/init_console.log"
        touch "${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/end_console.log"
        When run script cki/restraint/plugins/completed.d/80_finish_console_log
        The first line should equal "sleep 15"
        The line 2 should equal "curl --silent --show-error --retry 5 http://${LAB_CONTROLLER}:8000/recipes/${RSTRNT_RECIPEID}/logs/console.log -o ${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/end_console.log"
        The line 3 should equal "rstrnt-report-log -l ${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/test_console.log"
        The status should be success
    End

    It "can run 90_cleanup_cki"
        When run script cki/restraint/plugins/completed.d/90_cleanup_cki
        The first line should equal "rstrnt_info *** Running Plugin: cki/restraint/plugins/completed.d/90_cleanup_cki"
        The status should be success
    End
End

Describe 'cki-restraint: plugins concurrent task'
    cleanup(){
        rm -rf "${CURRENT_TASK_PATH}"
    }
    BeforeAll 'cleanup'
    AfterAll 'cleanup'

    It "can run 26_cki_environment first task"
        When run script cki/restraint/plugins/task_run.d/26_cki_environment
        The first line should equal "rstrnt_info *** Running Plugin: cki/restraint/plugins/task_run.d/26_cki_environment"
        The file "${CURRENT_TASK_PATH}/${RSTRNT_RECIPEID}/${RSTRNT_TASKID}/bootinfo" should be exist
        The status should be success
    End

    It "abort run 26_cki_environment with concurrent task"
        export RSTRNT_RECIPEID=54322
        export RSTRNT_TASKID=12346
        export RSTRNT_TASKNAME=concurrent-test-task
        export RSTRNT_RECIPE_URL="http://${LAB_CONTROLLER}:8000/recipes/${RSTRNT_RECIPEID}"
        When run script cki/restraint/plugins/task_run.d/26_cki_environment
        The first line should equal "rstrnt_info *** Running Plugin: cki/restraint/plugins/task_run.d/26_cki_environment"
        The line 2 should equal "rstrnt-report-result concurrent-test-task FAIL"
        The line 3 should equal "Aborting task ${RSTRNT_TASKID} from recipe ${RSTRNT_RECIPEID} as system expects to run tests for recipe 54321"
        The status should be success
    End
End
