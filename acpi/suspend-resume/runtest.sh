#!/bin/sh -x
# Include helper functions
. /mnt/tests/kernel/acpi/suspend-resume/include/runtest.sh

report_suspend() {
    method=$1
    state=$2
    count=$3
    echo 'Suspending now...' | tee -a ${OUTPUTFILE}
    report_result $TEST/$method-$state-$count/suspend PASS
}

# Execute designated suspend/resume
# $1 = method: how to set suspend resume, sysfs or rtcwake command
# $2 = state: sleep state to test (e.g. mem or disk)
# $3 = count: which number run of suspend/resume is this (first, second, etc)
suspend_resume() {
        method=$1
        state=$2
        count=$3

        echo "=============== Testing: $method $state - $count ====================" | tee -a ${OUTPUTFILE}
        # To avoid loops (e.g. after unexpected reboot), make sure this sleep state test has not been
        # previously executed. If it has, skip running the test and complain.
        if `grep -q $method-$state-$count "$SUSPEND_STATUS"`; then
                echo "This test has already been run!?! Did the system reboot? Skipping..." | tee -a ${OUTPUTFILE}
                report_result $TEST/$method-$state-$count/unexpected-rerun WARN
                return 1
        fi
        # If the system supports this sleep state then test
        suspend_state_support $state
        if [[ $suspend_state_support_result = PASS ]]; then
                echo $method-$state-$count >> "$SUSPEND_STATUS" # Record the test has been run
                     report_suspend $method $state $count
                     suspend_time recordStart
                        if [ $method = sysfs ]; then
                         suspend_sysfs $state
                     elif [ $method = rtcwake ]; then
                         suspend_rtcwake $state
                     fi
                     suspend_time recordEnd
                     acceptable_delta $SUSPENSION_TIME
                     sleep 30
                     if [[ $SUSPENDTIME == PASS ]]; then
                         echo "Successfully resumed!" | tee -a ${OUTPUTFILE}
                          report_result $TEST/$method-$state-$count/resume PASS
                     else
                         report_result $TEST/$method-$state-$count/resume FAIL
                     fi
        else
                echo "$suspend_state_support_description not supported, will not test!" | tee -a ${OUTPUTFILE}
                report_result $TEST/$method-$state-$count WARN
        fi
}

suspend_setup
if [[ $suspend_setup_result = PASS ]]; then
    report_result $TEST/setup PASS
elif [[ $suspend_setup_result = COMPLETED ]]; then
    echo "setup already completed"
fi

suspend_resume sysfs mem 1
suspend_resume sysfs mem 2
suspend_resume sysfs mem 3
suspend_resume sysfs disk 1
suspend_resume sysfs disk 2
suspend_resume sysfs disk 3

suspend_resume rtcwake mem 1
suspend_resume rtcwake mem 2
suspend_resume rtcwake mem 3
suspend_resume rtcwake disk 1
suspend_resume rtcwake disk 2
suspend_resume rtcwake disk 3

suspend_cleanup
exit 0
