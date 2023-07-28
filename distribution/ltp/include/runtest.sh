#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

# Source the common test script helpers
. "${CDIR}"/../../../cki_lib/libcki.sh || exit 1

# Set unique log file.
OUTPUTDIR=/mnt/testarea
if ! [ -d $OUTPUTDIR ]; then
    echo "Creating $OUTPUTDIR"
    mkdir -p $OUTPUTDIR
fi
LTPDIR=$OUTPUTDIR/ltp
OPTS=""

# Helper functions

# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
devnull=0

# Create debug log.
DEBUGLOG=`mktemp -p /mnt/testarea -t DeBug.XXXXXX`
SYSINFO=`mktemp -p /mnt/testarea -t SysInfo.XXXXXX`

# locking to avoid races
lck=$OUTPUTDIR/$(basename $0).lck

if [ -z ${ARCH} ]; then
    ARCH=$(uname -i)
fi

# by jstancek
check_cpu_cgroup ()
{
    # Move us to root cpu cgroup
    # see: Bug 773259 - tests don't run in root cpu cgroup with systemd

    cgroup2_mntpoint=$(mount | grep ^cgroup2 | awk '{print $3}')
    if [ -n "$cgroup2_mntpoint" ]; then
        echo "Found cgroup2 mount point, moving pid $$ to $cgroup2_mntpoint/cgroup.procs"
        echo $$ > $cgroup2_mntpoint/cgroup.procs
        return
    fi

    cpu_cgroup_mntpoint=$(mount | grep "type cgroup (.*cpu[,)]" | awk '{print $3}')

    [ -d $cpu_cgroup_mntpoint/system.slice/ ] || mkdir -p $cpu_cgroup_mntpoint/system.slice/
    cat $cpu_cgroup_mntpoint/cpu.rt_runtime_us > $cpu_cgroup_mntpoint/system.slice/cpu.rt_runtime_us

    cpu_path=$(cat /proc/self/cgroup | grep ":cpu[:,]" | sed "s/.*://")
    cat $cpu_cgroup_mntpoint/cpu.rt_runtime_us > $cpu_cgroup_mntpoint/$cpu_path/cpu.rt_runtime_us

    if [ -e /proc/self/cgroup ]; then
        grep -i "cpu[,:]" /proc/self/cgroup | grep -q ":/$"
        ret=$?
    else
        echo "Couldn't find /proc/self/cgroup." | tee -a $OUTPUTFILE
        ret=1
    fi

    if [ $ret -eq 0 ]; then
        echo "Running in root cpu cgroup" | tee -a $OUTPUTFILE
    else
        echo "cat /proc/self/cgroup" | tee -a $OUTPUTFILE
        cat /proc/self/cgroup | tee -a $OUTPUTFILE
        if [ -e "$cpu_cgroup_mntpoint/tasks" ]; then
            echo "Found root cpu cgroup tasks at: $cpu_cgroup_mntpoint/tasks" | tee -a $OUTPUTFILE
            echo $$ > $cpu_cgroup_mntpoint/tasks
            ret=$?
            if [ $ret -eq 0 ]; then
                echo "Succesfully moved (pid: $$) to root cpu cgroup." | tee -a $OUTPUTFILE
            else
                echo "Failed to move (pid: $$), ret code: $ret" | tee -a $OUTPUTFILE
            fi
        fi

        if [ $ret -ne 0 ]; then
            echo "Couldn't verify that we run in root cpu cgroup." | tee -a $OUTPUTFILE
            echo "Note that some tests (on RHEL7) may fail, see Bug 773259." | tee -a $OUTPUTFILE
        fi
    fi
}

# Log a message to the ${DEBUGLOG} or to /dev/null.
DeBug ()
{
    local msg="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if [ "$devnull" = "0" ]; then
        lockfile -r 1 $lck
        if [ "$?" = "0" ]; then
            echo -n "${timestamp}: " >>$DEBUGLOG 2>&1
            echo "${msg}" >>$DEBUGLOG 2>&1
            rm -f $lck >/dev/null 2>&1
        fi
    else
        echo "${msg}" >/dev/null 2>&1
    fi
}

DebugInfo ()
{
    DeBug "******* Requested Information $1 *******"
    DeBug "** IPCS Information **"
    /usr/bin/ipcs -a >> $DEBUGLOG
    DeBug "** msgmni Information **"
    cat /proc/sys/kernel/msgmni >> $DEBUGLOG
    DeBug "******* End Requested Information $1 *******"

    # Just for easy reading
    echo >> $DEBUGLOG
    if [ "$1" = "After" ] || [ "$1" = "AfterIPCRMCleanUp" ]; then
        echo >> $DEBUGLOG
    fi

}

PrintSysInfo ()
{
    echo "uname -rm" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    hostname | tee -a $SYSINFO
    uname -rm | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "lscpu" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    lscpu | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "numactl --hardware" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    numactl --hardware | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "cat /proc/meminfo" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    cat /proc/meminfo | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "lsblk" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    lsblk | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "dmsetup table" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    dmsetup table | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "df -Th" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    df -Th | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "fdisk -l" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    fdisk -l | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    echo "mount | column -t" | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO
    mount | column -t | tee -a $SYSINFO
    echo "-----" | tee -a $SYSINFO

    cp -f $SYSINFO ./systeminfo.txt
    SubmitLog ./systeminfo.txt
}

RprtRslt ()
{
    TEST=$1
    result=$2

    logfile_run=$OUTPUTDIR/$TEST.run.log
    logfile_fail=$OUTPUTDIR/$TEST.fail.log

    # Always upload parsed test log for those failed test cases
    GetFailureLog $logfile_run "None" > $logfile_fail
    [ -s $logfile_fail ] && SubmitLog $logfile_fail
    failed_tests=$(ls *.fail.log)
    for failed_test in $failed_tests; do
        # skip logfile_fail as it is not a test case fail log
        if [ "$failed_test" == "$logfile_fail" ]; then
            continue
        fi
        # upload the failed test output as part of restraint subtest
        # extract test case name from test case fail log
        rstrnt-report-result -o "$failed_test" "${failed_test%.fail.log}" FAIL
    done

    # each failure is reported as subtest, always report pass for the summary result
    SUMMARY_RESULT=PASS
    # in case result is FAIL, but for some reason there is no subtest fail log
    # like there is no python3 for GetFailureLog to parse the failures
    # make sure the summary has fail status, to make sure the test will have failed status
    if [[ -z "${failed_tests}" && "${result}" != "PASS" ]]; then
        SUMMARY_RESULT=FAIL
    fi
    # I want to see the succeeded running log as well
    SubmitLog $logfile_run
    score=$(cat $OUTPUTDIR/$RUNTEST.log | grep "Total Failures:" |cut -d ' ' -f 3)
    rstrnt-report-result "Summary ($TEST)" $SUMMARY_RESULT $score
}

SubmitLog ()
{
    LOG=$1

    rstrnt-report-log -l $LOG
}

CleanUp ()
{
    LOGFILE=$1

    if [ -e $OUTPUTDIR/$LOGFILE.run.log ]; then
        rm -f $OUTPUTDIR/$LOGFILE.run.log
    fi

    if [ -e $OUTPUTDIR/$LOGFILE.log ]; then
        rm -f $OUTPUTDIR/$LOGFILE.log
    fi
}

IPCRMCleanup ()
{
    # Clean up msgid
    DeBug "******* Start msgmni cleanup $1 *******"
    for i in `ipcs -q | cut -f2 -d' '`; do
        ipcrm -q $i
    done
    DeBug "******* End msgmni cleanup $1 *******"
    echo >> $DEBUGLOG
}

ChkTime ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: "$timestamp -> $1"
}

TimeSyncNTP ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: \
        "$timestamp -> Sync time with clock.redhat.com"

    ntpdate clock.redhat.com
}

EnableNTP ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: "$timestamp -> Enable NTP"
    service ntpd start
}

DisableNTP ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: "$timestamp -> Disable NTP"
    service ntpd stop
}

EnableKsmd ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: "$timestamp -> Enable ksmd and ksmtuned"
    service ksm start
    service ksmtuned start
}

DisableKsmd ()
{
    local timestamp=$(date '+%F %T')
    logger -p local0.notice -t TEST.INFO: "$timestamp -> Disable ksmd and ksmtuned"
    service ksm stop
    service ksmtuned stop
}

# Workaround for Bug 1263712 - OOM is sporadically killing more than just expected process
ProtectHarnessFromOOM ()
{
    for pid in $(pgrep systemd) $(pgrep restraintd) $(pgrep beah) $(pgrep rhts) $(pgrep ltp) $(pgrep dhclient) $(pgrep NetworkManager); do
        echo -16 > /proc/$pid/oom_adj
    done

    # make sure children of this process are not protected
    # as those include also OOM tests
    echo 0 > /proc/self/oom_adj
}

# Modify the $RUNTEST.log for eassier identifying KnownIssue case
LogDeceiver ()
{
    if ! [ -f ${LTPDIR}/KNOWNISSUE ]; then
        return
    fi

    for k in $(cat ${LTPDIR}/KNOWNISSUE | grep -v '^#'); do
        sed -i '/'$k'/ s/FAIL/KNOW/' $OUTPUTDIR/$RUNTEST.log
    done
}

skip_testcase ()
{
    # skip tests defined in var SKIPTESTS, seperated by space
    if [ -n "$SKIPTESTS" ]; then
        echo -e ${SKIPTESTS// /"\n"} > SKIPTESTS
        # skip file needs to be an absolute path or path relative to $LTPROOT
        # use absolute path here
        OPTS="$OPTS -S $PWD/SKIPTESTS"
    fi
}

RunTest ()
{
    RUNTEST=$1
    OPTIONS=$2 # pass other options here, like "-b /dev/sda5 -B xfs"

    ProtectHarnessFromOOM

    # disable AVC check only in CGROUP tests
    if echo $RUNTEST | grep -q CGROUP; then
        export AVC_ERROR='+no_avc_check'
    fi

    ChkTime $RUNTEST

    # Default result to Fail
    export result_r="FAIL"

    # Sync the time with the time server. Tests may change the time
    TimeSyncNTP

    if [ -n "$FILTERTESTS" ]; then
        FILTERTESTS="$(echo $FILTERTESTS | sed 's/\w\+/-e &/g')"
        time -p ${LTPDIR}/runltp -p -d $OUTPUTDIR -l $OUTPUTDIR/$RUNTEST.log \
            -o $OUTPUTDIR/$RUNTEST.run.log $OPTIONS -s "$FILTERTESTS"
    else
        DebugInfo Before
        DeBug "Command Line:"
        DeBug "${LTPDIR}/runltp -p -d $OUTPUTDIR -l $OUTPUTDIR/$RUNTEST.log \
            -o $OUTPUTDIR/$RUNTEST.run.log -f $RUNTEST $OPTIONS"
        time -p ${LTPDIR}/runltp -p -d $OUTPUTDIR -l $OUTPUTDIR/$RUNTEST.log \
            -o $OUTPUTDIR/$RUNTEST.run.log -f $RUNTEST $OPTIONS
    fi

    DebugInfo After
    if [ $RUNTEST = "ipc" ]; then
        IPCRMCleanup
        DebugInfo AfterIPCRMCleanup
    fi

    LogDeceiver

    if ! [ -e $OUTPUTDIR/$RUNTEST.log ] || grep -q FAIL $OUTPUTDIR/$RUNTEST.log; then
        echo "$RUNTEST Failed: " | tee -a $OUTPUTFILE
        result_r="FAIL"
    else
        echo "$RUNTEST Passed: " | tee -a $OUTPUTFILE
        result_r="PASS"
    fi

    cat $OUTPUTDIR/$RUNTEST.log >> $OUTPUTFILE
    echo Test End Time: `date` >> $OUTPUTFILE

    # If REPORT_FAILED_RESULT set to "yes", report every failed test to beaker
    # so that it's easier to see which tests failed.
    if [ "$REPORT_FAILED_RESULT" == "yes" -a "$result_r" == "FAIL" ]; then
        while read test res ret; do
            if [ "$res" != "FAIL" ]; then
                continue
            fi
            RprtRslt $RUNTEST/$test $res $ret
        done < $OUTPUTDIR/$RUNTEST.log
    fi
    RprtRslt $RUNTEST $result_r

    # Restore AVC check
    if echo $RUNTEST | grep -q CGROUP; then
        export AVC_ERROR=''
    fi
}

RunFiltTest ()
{
    if [ -n "$FILTERTESTS" ]; then
        rm -f $OUTPUTDIR/filtered_runtest.log
        rm -f $OUTPUTDIR/filtered_runtest.run.log

        RunTest filtered_runtest "$OPTS"
        return 0
    fi

    return 1
}

GetFailureLog ()
{
    local logfile=${1?"*** log file ***"}
    local kifile=${2?"*** known issue file ***"}
    local thisdir=$(dirname $(readlink -f $BASH_SOURCE))
    local parser=$thisdir/ltp_log_parser.py
    if ! python3 --version > /dev/null 2>&1; then
        echo "python3 is not installed, not parsing failures"
        return
    fi
    if [ $kifile == "None" ]; then
        python3 $parser -F -t 0 $logfile
    else
        python3 $parser -f $kifile -F -t 0 $logfile
    fi
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
    check_cpu_cgroup
fi
