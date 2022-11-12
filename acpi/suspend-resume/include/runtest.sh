#!/bin/sh -x

SLEEP_TIME=2  # In minutes
SUSPEND_STATUS=/tmp/suspend-resume.status  # Status file to indicate where we are in the test (in case of reboot)
START_TIME=/tmp/suspend-resume.start # used to record start time before suspend in order to calculate delta
# Source the common test script helpers
. /usr/bin/rhts-environment.sh

RELEASE=""
if grep -q "release 6" /etc/redhat-release; then
        RELEASE=rhel6
elif grep -q "release 5" /etc/redhat-release; then
        RELEASE=rhel5
fi

print_rtc() {
        echo '-- RTC Status: ----' | tee -a ${OUTPUTFILE}
        echo "*** System time: `date`" | tee -a ${OUTPUTFILE}
        if [ $RELEASE = rhel5 ]; then
                echo "*** /proc/acpi/alarm:" | tee -a ${OUTPUTFILE}
                cat /proc/acpi/alarm | tee -a ${OUTPUTFILE}
        fi

        echo "*** /proc/driver/rtc:" | tee -a ${OUTPUTFILE}
        cat /proc/driver/rtc | tee -a ${OUTPUTFILE}
        echo '-------------------' | tee -a ${OUTPUTFILE}
}

suspend_sysfs() {
        state=$1
        avoid_reboot_hibernation $state
        print_rtc
        echo "Setting RTC alarm to now + $SLEEP_TIME minutes..." | tee -a ${OUTPUTFILE}
        if [ $RELEASE = rhel6 ]; then
                echo 0 > /sys/class/rtc/rtc0/wakealarm
                echo `date -u -d "+ $SLEEP_TIME minutes" '+%s'` > /sys/class/rtc/rtc0/wakealarm
        elif [ $RELEASE = rhel5 ]; then
                echo `date -u -d "+ $SLEEP_TIME minutes" '+%F %T'` > /proc/acpi/alarm
        fi
        print_rtc

        # weird things can happen in beaker report if
        # there is no flush before suspend
        rhts-flush

        echo $state > /sys/power/state
        RES=$?

        if [[ $RES != 0 ]]; then
                    echo "WARN: echo to /sys/power/state failed, suspend may fail" | tee -a ${OUTPUTFILE}

        fi

}

suspend_rtcwake() {
        state=$1
        avoid_reboot_hibernation $state
        echo "Setting RTC alarm to now + $SLEEP_TIME minutes..." | tee -a ${OUTPUTFILE}
        if [ $RELEASE = rhel6 ]; then
                # weird things can happen in beaker report if
                # there is no flush before suspend
                rhts-flush
                rtcwake -m $state -t `date -u -d "+ $SLEEP_TIME minutes" '+%s'` | tee -a ${OUTPUTFILE}
        elif [ $RELEASE = rhel5 ]; then
                echo "RHEL 5 doesn't have rtcwake/util-linux-ng.rpm" | tee -a ${OUTPUTFILE}
        fi
}
setup_time() {
    if [[ ! -a time ]]; then
        echo "time binary doesn't exist, does source file exist?"
        if [[ ! -a time.c ]]; then
            echo "time.c doesn't exist, create it" | tee -a ${OUTPUTFILE}
            cat > time.c <<EOF
#include <stdio.h>
#include <time.h>

int main(int argc, const char *argv[])
{
    time_t result;

    result = time(NULL);

    printf("%s%ju secs since the Epoch\n",
            asctime(localtime(&result)),
            result);

    return 0;
}
EOF
            echo "now compile time.c" | tee -a ${OUTPUTFILE}
            gcc -o time time.c
        else
            echo "time.c already exists, compile it" | tee -a ${OUTPUTFILE}
            gcc -o time time.c
        fi
        fi

}

suspend_setup() {
        echo '=============== Setup ==================================' | tee -a ${OUTPUTFILE}
        echo "Supported sleep states: `cat /sys/power/state`" | tee -a ${OUTPUTFILE}

        touch "$SUSPEND_STATUS"
        if ! `grep -q setup "$SUSPEND_STATUS"` ; then
                echo "First pass. Configuring system and then will reboot." | tee -a ${OUTPUTFILE}
                # Set the system to UTC to avoid problems with RTC alarm. Backup and then restore later.
                if [ ! -e /etc/localtime.orig ]; then cp /etc/localtime /etc/localtime.orig ; fi
                cp -f /usr/share/zoneinfo/UTC /etc/localtime

                # For debugging purposes, don't suspend serial console
                default=`grubby --default-kernel`
                grubby --args="no_console_suspend" --update-kernel=$default

                # compile time.c into time so we can check time before/after suspending
                setup_time

                # Record that setup completed and then reboot
                echo setup >> "$SUSPEND_STATUS"
                echo "Rebooting now..." | tee -a ${OUTPUTFILE}
                suspend_setup_result=PASS
                rhts-reboot
        else
                echo "Second pass. Continuing." | tee -a ${OUTPUTFILE}
                suspend_setup_result=COMPLETED
        fi

        # Sync up system and hardware clocks
        hwclock -w
}

suspend_cleanup() {
        echo '=============== Clean up ==================================' | tee -a ${OUTPUTFILE}
        rm -f "$SUSPEND_STATUS"
        rm -f "$START_TIME"
        cp -f /etc/localtime.orig /etc/localtime
}



avoid_reboot_hibernation() {
    state_=$1
    if [[ $state_ = disk ]]; then
            hibernation_mode=`cat /sys/power/disk | sed 's/\(.*\)\[\(.*\)\]\(.*\)/\2/g'`

            # reboot mode
            if [[ $hibernation_mode = reboot ]]; then
                    if grep -q platform /sys/power/disk; then
                            echo "Setting to platform hibernation mode" | tee -a ${OUTPUTFILE}
                            echo "platform" > /sys/power/disk
                    elif grep -q shutdown /sys/power/disk; then
                              echo "Setting to shutdown hibernation mode" | tee -a ${OUTPUTFILE}
                            echo "shutdown" > /sys/power/disk
                    else
                            echo "working in reboot hibernation mode" | tee -a ${OUTPUTFILE}
                    fi
            else
                    echo "working in $hibernation_mode hibernation mode" | tee -a ${OUTPUTFILE}
            fi
    fi
}

boottime_stability() {
    pass=$1
    boottime_stability_result=PASS
    BTIMECOUNT=1000000
    if [[ $pass = first ]]; then
        BOOTTIME_1=`cat /proc/stat | grep "btime" | awk '{print $2}'`
    elif [[ $pass = second ]]; then
        while [ $BTIMECOUNT -ge 0 ]
        do
            BOOTTIME_2=`cat /proc/stat | grep "btime" | awk '{print $2}'`
            if [[ $BOOTTIME_1 != $BOOTTIME_2 ]]; then
                printf "FAIL: boottime not stable count = $COUNT\n\t * Before suspend to $i boottime = $BO\
OTTIME_1\n\t * After  suspend to $i boottime = $BOOTTIME_2\n" | tee -a ${OUTPUTFILE}

                boottime_stability_result=FAIL
                break;
            fi

            ((BTIMECOUNT--))
        done
    fi
}

suspend_time() {
    timeArg=$1
    if [ $timeArg = recordStart ]; then
        echo `./time | sed -n 2p | awk '{ print $1 }'` > $START_TIME
    elif [ $timeArg = recordEnd ]; then
        END_TIME=`./time | sed -n 2p | awk '{ print $1 }'`
        # If we have END_TIME we must have gotten START_TIME and can
        # do math to see if suspend happened within reasonable amount of time
        SUSPENSION_TIME=`expr $END_TIME - $(cat $START_TIME)`
        echo "suspension time is $SUSPENSION_TIME seconds" | tee -a ${OUTPUTFILE}

    else
        echo "suspend_time() called without either recordStart or recordEnd"  | tee -a ${OUTPUTFILE}
    fi
}

acceptable_delta() {
    suspendedTime=$1
    expected_delta=$2
    target=`expr $SLEEP_TIME \* 60`

    if [[ -n $2 ]]; then
        echo "expected delta time of +-$expected_delta of $target" | tee -a ${OUTPUTFILE}

        lowLimit=$((target-expected_delta))
        highLimit=$((target+expected_delta))

        if [[ $suspendedTime -ge $lowLimit && $suspendedTime -le $highLimit ]]
        then
            SUSPENDTIME=PASS
        else
            SUSPENDTIME=FAIL
        fi
    else
        echo "no expected_delta passed to acceptable_delta()" | tee -a ${OUTPUTFILE}
        echo "just make sure suspendedTime was >= $SLEEP_TIME minutes" | tee -a ${OUTPUTFILE}
        if [[ $suspendedTime -ge $target ]]; then
            SUSPENDTIME=PASS
        else
            SUSPENDTIME=FAIL
        fi
     fi


    echo "acceptable delta  $SUSPENDTIME" | tee -a ${OUTPUTFILE}
}

suspend_state_support() {
    if [ $1 = mem ]; then
        suspend_state_description="Suspend-to-RAM (s3)"
    elif [ $1 = disk ]; then
        suspend_state_description="Suspend-to-Disk/Hibernate (s4)"
    fi

    if `grep -q $1 /sys/power/state`; then
        echo "$suspend_state_description $1 supported" | tee -a ${OUTPUTFILE}
        suspend_state_support_result=PASS
    else
        echo "$suspend_state_description $1 NOT supported" | tee -a ${OUTPUTFILE}
        suspend_state_support_result=FAIL
    fi
}

