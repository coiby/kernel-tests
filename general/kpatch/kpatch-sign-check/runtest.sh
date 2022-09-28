#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh
  PACKAGE="kernel"
    rlJournalStart
        rlPhaseStartTest "kpatch sign check"
        # When using live patch (from 7.5) in-kernel support, there is no kpatch.ko provided in any more.
        test -d /sys/kernel/livepatch && use_livepatch=1
        rlRun "rpm -qa kpatch" 0 "core module is installed"
        rlRun "rpm -qa kpatch-patch\*" 0 "patch  module is installed"
        [ "$use_livepatch" = 1 ] || rlRun " lsmod |grep 'kpatch '" 0 "core module already loaded"
        rlRun "lsmod |grep '^kpatch_'" 0 "patch module already loaded"
        KPATCHPATH=${KPATCHPATH:-$(rpm -ql `rpm -qa kpatch-patch\*`  |grep "/`uname -r`/" |grep "kpatch.ko")}
        # When using live patch (from 7.5) in-kernel support, there is no kpatch.ko provided in any more.
        [ "$use_livepatch" = 1 ] || rlRun "modinfo $KPATCHPATH | grep 'Red Hat Enterprise Linux kpatch signing key'" 0 "core module is signed"
        TMP=$(kpatch list |grep "`uname -r`")
        MODULEFILENAME=${MODULEFILENAME:-${TMP%% *}}
        rlRun "kpatch info $MODULEFILENAME |grep 'Red Hat Enterprise Linux kpatch signing key'" 0 "patch module is signed"
        taintvalue=`cat /proc/sys/kernel/tainted `
        rlRun "cat /proc/sys/kernel/tainted" -l 0-255
        rlRun -l "dmesg |grep kpatch" 0-254
        #https://bugzilla.redhat.com/show_bug.cgi?id=1090549 , KOT are supposed to the for the kpatch-patch
        #the value should be $(( ((1<<12)) + ((1<<15)) + ((1<<29)) )) = 536907776
        #There is not TECH_PREVIEW any more after RHEL-7.2.
        for taint in 1 2 4 8 16 32 64 128 256 512 1024 268435456 536870912 36864;
        do
           taintedtmp=`echo $taintvalue $taint|gawk 'and($1, $2) {print $2} '`
           if  [ -n "$taintedtmp" ];then
             tainted=$taintedtmp
           fi
        done
        if [ -n "$tainted" ];then
              rlPass "tainted is $taintvalue and it's index  $tainted is correct."
         else
             rlFail "tainted index  $tainted is NULL"
       fi
        rlPhaseEnd
    rlJournalEnd
