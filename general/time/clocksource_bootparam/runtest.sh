#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1
. ../../../cmdline_helper/libcmd.sh || exit 1

TEST="general/time/clocksource_bootparam"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')


function runtest()
{
    avail_cs=$(cat /sys/devices/system/clocksource/clocksource0/available_clocksource)
    current_cs=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
    echo "available clocksource: $avail_cs"
    if [ $RSTRNT_REBOOTCOUNT -eq 0 ]; then
        if [[ $avail_cs =~ "tsc" ]]; then
            change_cmdline "clocksource=tsc"
            sync; sleep 10
            rstrnt-reboot
        else
            echo "NO TSC CLOCKSOURCE"
            rstrnt-report-result $TEST SKIP 0
            exit 0
        fi
    fi
    if [ $RSTRNT_REBOOTCOUNT -eq 1 ]; then
        verify_cmdline "clocksource=tsc"
        echo "current clocksource: $current_cs"
        if [[ $current_cs =~ "tsc" ]]; then
            rstrnt-report-result $TEST PASS 0
        else
            rstrnt-report-result $TEST FAIL 1
        fi
        change_cmdline "-clocksource=tsc"
        sync; sleep 10
        rstrnt-reboot
    fi
    if [ $RSTRNT_REBOOTCOUNT -eq 2 ]; then
        verify_cmdline "-clocksource=tsc"
        echo "All tests finished!"
    fi
}

# ---------- Start Test -------------
runtest
exit 0
