#!/bin/sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TEST="standards/usex"

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

function setup()
{
    make all
    if [ $? -ne 0 ]; then
        rldie "fail to make the file. Aborting test..."
    fi
}

function SysStats()
{
    # Collect some stats prior to running the test
    echo "***** System stats *****"
    vmstat
    echo "---"
    free -m
    echo "---"
    cat /proc/meminfo
    echo "---"
    cat /proc/slabinfo
    echo "***** System stats *****"

    touch $OUTPUTDIR/logger.txt
    logger -t USEXINFO -f $OUTPUTDIR/logger.txt
}

function VerboseCupsLog()
{
   # This funnction was added Nov 2010 in hopes of assisting in resoltion of bugzilla 452305
   # See comment #31 https://bugzilla.redhat.com/show_bug.cgi?id=452305
   # Provide more verbose debug logging in /var/log/cups/error_log
   echo "-------------------------------------------------------------------------"
   echo "Setting up verbose debug logging in /var/log/cups/error_log for BZ452305."
   echo "-------------------------------------------------------------------------"
   rstrnt-backup /etc/cups/cupsd.conf
   sed -i -e 's,^LogLevel.*,LogLevel debug2,' /etc/cups/cupsd.conf
   sed -i -e '/^MaxLogSize/d' /etc/cups/cupsd.conf
   echo MaxLogSize 0 | tee -a /etc/cups/cupsd.conf
   sed -i -e '/^Browsing/d' /etc/cups/cupsd.conf
   sed -i -e '/^DefaultShared/d' /etc/cups/cupsd.conf
   echo "Browsing No" | tee -a /etc/cups/cupsd.conf
   echo "DefaultShared No" | tee -a /etc/cups/cupsd.conf
   # sed will create temporary file in /etc/cups and rename it to cupds.conf
   # so file ends up with wrong label
   restorecon /etc/cups/cupsd.conf
   # start service before using cupsctl
   (rlServiceStop cups && rlServiceStart cups)
   echo "cupsctl: "
   cupsctl
}

function TestUsexMain ()
{
    # verify to not run on s390x
    if [ "$(uname -m)" = "s390x" ]; then
        rlLog "s390x is not supported arch"
        return
    fi

    RHELVER=""
    cat /etc/redhat-release | grep "^Fedora"
    if [ $? -ne 0 ]; then
        RHELVER=$(cat /etc/redhat-release |sed 's/.*\(release [0-9]\).*/\1/')
    fi

    if [ -z "$RHELVER" ]; then
        kernel_rhelver=$(uname -r | grep -o "el[0-9]")
        echo "Taking release from kernel version: $kernel_rhelver"

        if [ "$kernel_rhelver" == "el6" ]; then
            RHELVER="release 6"
        fi

        if [ "$kernel_rhelver" == "el7" ]; then
            RHELVER="release 7"
        fi
    fi

    echo "RHELVER is $RHELVER"

    INFILE=rhtsusex.tcf
    MYARCH=$(arch)
    if [ "$MYARCH" = "x86_64" ] || [ "$MYARCH" = "s390x" ]; then
        rm -f /usr/lib/libc.a
        ln -s /usr/lib64/libc.a /usr/lib/libc.a
    fi

    if [ -z "$OUTPUTDIR" ]; then
        OUTPUTDIR=/mnt/testarea
    fi

    #if ppc64 has less than or equal to 1 GB of memory don't run the vm tests
    ONE_GB=1048576
    if [ "$MYARCH" = "ppc64" ]; then
        mem=`cat /proc/meminfo |grep MemTotal|sed -e 's/[^0-9]*\([0-9]*\).*/\1/'`
        test "$mem" -le "$ONE_GB" && INFILE=rhtsusex_lowmem.tcf
        logger -s "Running the rhtsusex_lowmem.tcf file"
    fi

    SysStats

    USEX_LOG="usex_log.txt"
    if [ "x$RHELVER" == "xrelease 6" ]; then
        logger -s "Running $RHELVER configuration"
        ./usex --rhts hang-trace --exclude=ar,strace,clear -i $INFILE -l $USEX_LOG --nodisplay -R $OUTPUTDIR/report.out
    elif [ "x$RHELVER" == "xrelease 7" ]; then
        logger -s "Running $RHELVER configuration"
        ./usex --rhts hang-trace --exclude=ar,as,strace,clear -i $INFILE -l $USEX_LOG --nodisplay -R $OUTPUTDIR/report.out
    else
        logger -s "Running default configuration"
        ./usex --rhts hang-trace --exclude=clear -i $INFILE -l $USEX_LOG --nodisplay -R $OUTPUTDIR/report.out
    fi

    # Default result to FAIL
    export result="FAIL"
    # Then post-process the results to find the regressions
    export fail=`cat $OUTPUTDIR/report.out | grep "USEX TEST RESULT: FAIL" | wc -l`

    rlFileSubmit $OUTPUTDIR/report.out
    rlFileSubmit $OUTPUTDIR/logger.txt
    rlFileSubmit $USEX_LOG

    if [ "$fail" -gt "0" ]; then
        export result="FAIL"
        rlFail "$TEST $result $fail"
    else
        export result="PASS"
        rlPass "$TEST $result $fail"
    fi
    echo 'Test' $TEST
    echo 'Result' $result
    echo 'fail' $fail
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        setup
    rlPhaseEnd
    rlPhaseStartTest "Usex test run"
        TestUsexMain
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
