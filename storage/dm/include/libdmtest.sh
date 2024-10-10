#!/bin/bash

# shellcheck source=/dev/null
source ../../../cki_lib/libcki.sh

DATETIME=$(date +"%Y%m%d%H%M%S")

function report_results
{
    local result=$CKI_PASS;
    output=$(./dmtest list --state FAIL --result-set "$1" | grep -oP '([\w-]+)\s+(?= FAIL)')
    for i in $output; do
        log_file=/tmp/"$i"-"$DATETIME"-FAIL.log
        ./dmtest log --with-dmesg --result-set "$1" "$i" > "$log_file";
        result=$CKI_FAIL
        # report resuls as subtests if running with restraint
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result -o "$log_file" "${i}" FAIL
    done

    popd || return "$CKI_FAIL"
    # Only report general results in case of pass, if there are failures
    # they are reported already individually as restraint subtests
    if [[ "$result" == "$CKI_PASS" ]]; then
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "Test" PASS
    fi

    # if running as restraint job, the test result is already reported as subtests
    # don't exit with values different of 0. Otherwise, restraint reports it as a separate subtest
    if [ "$result" -eq "$CKI_FAIL" ] ; then
        # exit with error in case it doesn't run as restraint
        [[ -n $RSTRNT_TASKID ]] || exit 1
    fi

    if [ "$result" -eq "$CKI_UNINITIATED" ] ; then
        rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
        exit 0
    fi
}

function startup
{
    echo "INFO: Installing testsuite"
    if ! ts_setup &> setup.log ; then
      cat setup.log
      echo "Aborting test as it failed to setup test suite."
      rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
      exit 0
    fi

    echo "INFO: testsuite installed successfully. More information on setup.log"
    [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result -o setup.log "Setup" PASS
}
