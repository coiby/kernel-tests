#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/clocksource_bootparam"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

function runtest()
{
    avail_cs=$(cat /sys/devices/system/clocksource/clocksource0/available_clocksource)
    current_cs=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
    bootparam=$(cat /proc/cmdline)
    DEFAULT=`grubby --default-kernel`
    echo "available clocksource: $avail_cs"
    if [ $RSTRNT_REBOOTCOUNT -eq 0 ]; then
        if [[ $avail_cs =~ "tsc" ]]; then
            grubby --args="clocksource=tsc" --update-kernel=$DEFAULT
            sync; sleep 10
            rstrnt-reboot
        else
            echo "NO TSC CLOCKSOURCE"
            rstrnt-report-result $TEST SKIP
            exit 0
        fi
    fi
    if [ $RSTRNT_REBOOTCOUNT -eq 1 ]; then
        echo "boot parameter: $bootparam"
        if [[ $bootparam =~ "clocksource=tsc" ]]; then
            rstrnt-report-result "add-clocksource=tsc" "PASS" 0
        else
            rstrnt-report-result "add-clocksource=tsc" "FAIL" 1
        fi
        echo "current clocksource: $current_cs"
        if [[ $current_cs =~ "tsc" ]]; then
            rstrnt-report-result $TEST PASS 0
        else
            rstrnt-report-result $TEST FAIL 1
        fi
        grubby --remove-args="clocksource=tsc" --update-kernel=$DEFAULT
        sync; sleep 10
        rstrnt-reboot
    fi
    if [ $RSTRNT_REBOOTCOUNT -eq 2 ]; then
        echo "boot parameter: $parameter"
        if [[ $bootparam =~ "clocksource=tsc" ]]; then
            rstrnt-report-result "remove clocksource=tsc" FAIL 1
        else
            rstrnt-report-result "remove-clocksource=tsc" PASS 0
        fi
        echo "All test finished!"
    fi
}

# ---------- Start Test -------------
runtest
exit 0
