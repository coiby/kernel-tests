#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/hwclock"

[ -z $RSTRNT_REBOOTCOUNT ] && {
    echo "RSTRNT_REBOOTCOUNT not set - setting to 0 for manual run" | tee -a $OUTPUTFILE
    export RSTRNT_REBOOTCOUNT=0
}

function timeZone ()
{
    ZONE=`echo $1 | sed 's/\(.*\)\/\(.*\)/\2/g'`

    echo "Setting the Time Zone $ZONE" | tee -a  $OUTPUTFILE 

    /bin/cp $1 /etc/localtime

    # detect Hardware Clock is kept in Coordinated Universal Time or local time
    HW=`hwclock -r --debug  | grep "Hardware clock is on" | awk '{ print $5}'`
    if [[ $HW = "UTC" ]]; then
        echo "Setting the RTC Clock kept in local time" | tee -a  $OUTPUTFILE
        hwclock -w --localtime
    else
        hwclock -w
    fi

    echo "### strart reboot count = ${RSTRNT_REBOOTCOUNT} Zone $ZONE" | tee -a ${OUTPUTFILE}
    rstrnt-reboot
}

function timeCheck ()
{
    hwclock -r --debug > /tmp/HWCLOCK
    HW=`cat /tmp/HWCLOCK | grep "Hardware clock is on" | awk '{ print $5 }'`

    if [[ $HW = "UTC" ]]; then
        echo "The RTC kept in Coordinated Universal Time" | tee -a  $OUTPUTFILE

        # HW_TIME=`cat /tmp/HWCLOCK | grep "Hw clock time" | sed  's/\(.*\) :\(.*\) =\(.*\)/\2/g'`
        HW_TIME=`cat /tmp/HWCLOCK | grep "Hw clock time" | sed  's/\(.*\) :\(.*\) =\(.*\)/\2/g' | cut -d " " -f 3`
        printf " * RTC UTC time $HW_TIME\n" | tee -a  $OUTPUTFILE

        LOCAL_TIME=`tail -n 1 /tmp/HWCLOCK | awk '{ print $5 }'`
        printf " * LOCAL   time $LOCAL_TIME\n" | tee -a  $OUTPUTFILE
    else
        echo "The RTC kept in Local Time" | tee -a  $OUTPUTFILE

        HW_TIME=`cat /tmp/HWCLOCK | grep "Hw clock time" | sed  's/\(.*\) :\(.*\) =\(.*\)/\2/g' | cut -d " " -f 3`
        printf " * RTC UTC time $HW_TIME\n" | tee -a  $OUTPUTFILE

        LOCAL_TIME=`tail -n 1 /tmp/HWCLOCK | awk '{ print $5 }'`
        printf " * LOCAL   time $LOCAL_TIME\n" | tee -a  $OUTPUTFILE

        :||{
        if [[ $HW_TIME != $LOCAL_TIME ]]; then
            echo "Fail(Local Time): time check failed hw time and localtime not equal" | tee -a  $OUTPUTFILE
            return 1
        fi
        }
    fi
}

function runtest ()
{
    # get the current zone information
    KERNEL_ZONE=`./time_zone | cut -d ':' -f 2`
    printf "Current kernel timezone (systz) :$KERNEL_ZONE \n" | tee -a  $OUTPUTFILE

    timeCheck $KERNEL_ZONE
    RES=$?

    # Start change time zone reboot.
    if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
        # East
        echo "Change time_zone to Europe/Prague" | tee -a $OUTPUTFILE
        timeZone /usr/share/zoneinfo/Europe/Prague
    elif [[ "${RSTRNT_REBOOTCOUNT}" -eq 1 ]]; then
        # CST
        echo "Change time_zone to Asia/Shanghai" | tee -a $OUTPUTFILE
        timeZone /usr/share/zoneinfo/Asia/Shanghai
    elif [[ "${RSTRNT_REBOOTCOUNT}" -eq 2 ]]; then
        # UTC
        echo "Change time_zone to UTC" | tee -a $OUTPUTFILE
        timeZone /usr/share/zoneinfo/UTC
    elif [[ "${RSTRNT_REBOOTCOUNT}" -eq 3 ]]; then
        # West
        echo "Change time_zone to America/New_York" | tee -a $OUTPUTFILE
        timeZone /usr/share/zoneinfo/America/New_York
    else
        echo "ALL rebooting action done" | tee -a  $OUTPUTFILE

        if [[ $RES != 0 ]]; then
            echo "=> Test Fail and No panic occurs" | tee -a  $OUTPUTFILE
            rstrnt-report-result $TEST "FAIL" 1
        else
            echo "=> Test Pass and No panic occurs" | tee -a  $OUTPUTFILE
            rstrnt-report-result $TEST "PASS" 0
        fi
    fi
}

# ---------- Start Test -------------
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -o time_zone time_zone.c

if [ $rhel_major -ge 8 ]; then
    systemctl stop chronyd
    runtest
    systemctl start chronyd
else
    service ntpd stop > /dev/null 2>&1
    runtest
    service ntpd start > /dev/null 2>&1
fi

exit 0
