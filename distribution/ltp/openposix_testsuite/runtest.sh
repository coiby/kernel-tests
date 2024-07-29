#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source the common test script helpers
. ../../../cki_lib/libcki.sh || exit 1
. ../include/runtest.sh      || exit 1
. ../include/kvercmp.sh      || exit 1
. ../include/ltp-make.sh     || exit 1
. ../include/knownissue.sh   || exit 1

#export AVC_ERROR=+no_avc_check
#export RHTS_OPTION_STRONGER_AVC=

function ltp_test_build()
{
    download_ltp

    # if TEST_VERSION is set, use the --forward flag so patches which are
    # already applied do not cause the entire job to fail, and ignore
    # the exit status (which will be 1 for an error even with --forward)
    if [ ! -n "$TEST_VERSION" ]
    then
        export PATCH="patch -p1 -d ${TARGET}"
    else
        export PATCH="patch --forward -p1 -d ${TARGET}"
    fi

    #Patch-inc
    echo "============ Patch openposx patch-inc ===============" | tee -a $OUTPUTFILE
    patch-inc > patchinc.log 2>&1
    cat patchinc.log | tee -a $OUTPUTFILE

    echo "============ Patch openposix test suite =============" | tee -a $OUTPUTFILE
    #upstream
    cp -fv patches/pthread_cancel/3-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/pthread_cancel/3-1.c
    cp -fv patches/pthread_rwlock_rdlock/4-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/pthread_rwlock_rdlock/4-1.c

    if [ "$TESTVERSION"  == "20120822" ]; then
        cp -fv patches/20120822/pthread_cond_broadcast-1-2.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/pthread_cond_broadcast/1-2.c
        cp -fv patches/20120822/sigset-6-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/sigset/6-1.c
        cp -fv patches/20120822/sigset-7-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/sigset/7-1.c
        cp -fv patches/20120822/pthread_cond_signal-1-1.c $TARGET/testcases/open_posix_testsuite/conformance/interfaces/pthread_cond_signal/1-1.c
    fi

    if [ "$TESTVERSION"  == "20130109" ]; then
        cp -fv patches/20130109/aio_fsync-2-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/aio_fsync/2-1.c
        cp -fv patches/20130109/aio_fsync-3-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/aio_fsync/3-1.c
    fi

    if [ "$TESTVERSION"  == "20130904" ]; then
        cp -fv patches/20130904/2-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/pthread_attr_setschedpolicy
    fi

    if [ "$TESTVERSION"  == "20140115" ]; then
        cp -fv patches/20140115/run-tests.sh ${TARGET}/testcases/open_posix_testsuite/bin
    fi

    if [ "$TESTVERSION"  == "20140422" ]; then
        cp -fv patches/20140422/run-tests.sh ${TARGET}/testcases/open_posix_testsuite/bin
    fi

    if [ "$TESTVERSION"  == "20220121" ]; then
        cp -vf patches/20220121/2-1.c ${TARGET}/testcases/open_posix_testsuite/conformance/interfaces/lio_listio/2-1.c
    fi
}


if [ -z "$RSTRNT_REBOOTCOUNT" ]; then
     RSTRNT_REBOOTCOUNT=0
fi

cver=$(uname -r)
echo "Current kernel is: $cver" | tee -a $OUTPUTFILE

# ---------- Start Test -------------
if [ "${RSTRNT_REBOOTCOUNT}" -ge 1 ]; then
    echo "============ Test has already been run, Check logs for possible failures ============" | tee -a $OUTPUTFILE
    # This can happen, for example, if hit a kernel panic
    # the panic message might have been saved on journal
    if type -p journalctl > /dev/null; then
        JOURNALCTLLOG=/tmp/journalctl.log
        journalctl > "${JOURNALCTLLOG}"
        SubmitLog "${JOURNALCTLLOG}"
    fi
    rstrnt-report-result Abnormal-Reboot  WARN/ABORTED
    rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    exit
fi

if type -p journalctl > /dev/null; then
    # if /var/log/journal doesn't exist create it to make logs persistent
    if [ ! -d /var/log/journal ]; then
        echo "INFO: enabling persistent storage for journalctl"
        mkdir -p /var/log/journal
        journalctl --flush
    fi
fi

# report patch errors from ltp/include
grep -i -e "FAIL" -e "ERROR" patchinc.log > /dev/null 2>&1
if [ $? -eq 0 ]; then
    rstrnt-report-result "ltp-include-patch-errors" WARN/ABORTED
    rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    exit
fi

# Sometimes it takes too long to waiting for syscalls finish and I want
# to know whether the compilation is finish or not.
rstrnt-report-result "install" "PASS"

echo "ulimit -c unlimited" | tee -a $OUTPUTFILE
ulimit -c unlimited

echo "numactl --hardware" | tee -a $OUTPUTFILE
echo "-----" | tee -a $OUTPUTFILE
numactl --hardware > ./numactl.txt 2>&1
cat ./numactl.txt | tee -a $OUTPUTFILE
rm -f ./numactl.txt > /dev/null 2>&1
echo "-----" | tee -a $OUTPUTFILE

# disable NTP and chronyd
tservice=""
pgrep chronyd > /dev/null
if [ $? -eq 0 ]; then
    tservice="chronyd"
    service chronyd stop
fi
DisableNTP


# Build ltp test
ltp_test_build

# START TEST
opt_dir="$(pwd)/ltp-*/testcases/open_posix_testsuite"
opt_dir="$(ls -1 -d $opt_dir | head -1)"
echo "Open POSIX testsuite is at: $opt_dir" | tee -a $OUTPUTFILE

# give more slack to known issues with high steal time on s390x
if uname -r | grep -q s390; then
    echo "s390: patching ACCEPTABLEDELTA for timer_settime testcases" | tee -a $OUTPUTFILE
    sed -i 's/#define ACCEPTABLEDELTA 1/#define ACCEPTABLEDELTA 9/' $opt_dir/conformance/interfaces/timer_settime/*.c
fi

# disable unsupported/known to fail testcases
DISABLED_LIST='disabled.common'

# Data written beyond the end of partial-page mmap can be seen by subsequent
# maps when using tmpfs so this test fails. See mmap(2) man page for more info.
if grep -q '/tmp tmpfs' /proc/mounts; then
    echo './conformance/interfaces/mmap/11-4.c' >> ${DISABLED_LIST}
fi

#
# mlock_8-1, munlock_10-1
# http://lists.linux.it/pipermail/ltp/2019-October/013912.html
# 597399d0cb91 ("arm64: tags: Preserve tags for addresses translated via TTBR1")
# d0022c0ef29b ("arm64: memory: Add missing brackets to untagged_addr() macro")
#
if is_arch "aarch64" && kernel_in_range "0" "5.6.0"; then
    echo './conformance/interfaces/mlock/8-1.c' >> $DISABLED_LIST
    echo './conformance/interfaces/munlock/10-1.c' >> $DISABLED_LIST
fi

echo "Disabling testcases" | tee -a $OUTPUTFILE
for entry in $(cat $DISABLED_LIST); do
    first_char=$(echo $entry | cut -b1)
    if [ "$first_char" == "#" ]; then
        continue
    fi
    echo "Disabling: $entry" | tee -a $OUTPUTFILE
    rm -rf "${opt_dir:?}"/$entry >> $OUTPUTFILE 2>&1
done

# build
echo "Building testcases" | tee -a $OUTPUTFILE
pushd $opt_dir
if [[ "$TESTVERSION" -lt "20220930" ]]; then
    env CFLAGS="-g3" time make all > buildlog.txt 2>&1
else
    echo $opt_dir | grep -q '/ltp-full-' || make autotools
    env CFLAGS="-g3" time ./configure && make all > buildlog.txt 2>&1
fi
if [ $? -ne 0 ]; then
    bzip2 buildlog.txt
    SubmitLog buildlog.txt.bz2
    rstrnt-report-result build WARN/ABORTED
    rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    exit
else
    rstrnt-report-result build PASS
fi
popd

OUTPUTFILE="$OUTPUTFILE.2"
echo "Executing testcases" | tee -a $OUTPUTFILE
time make -C $opt_dir test > logfile.runall 2>&1

# log failed TESTCASES
grep -e FAILED -e SIGNALED -e ABNORMALLY logfile.runall | sed 's/:.*//' > failed_list

# Some testcases are testing for conditions which can happen
# in very limited time window, for example: attempt to cancel
# ongoing aio operation, depending on timing such operation
# can complete asynchronously before testcase issues cancel.
# In this case testcase ends with UNRESOLVED, do not report
# it as failure.
grep -e UNRESOLVED logfile.runall | sed 's/:.*//' > unresolved_list
sed -i '/.*aio_error_2-1/d' unresolved_list
sed -i '/.*aio_cancel_4-1/d' unresolved_list
sed -i '/.*aio_cancel_5-1/d' unresolved_list
sed -i '/.*aio_cancel_6-1/d' unresolved_list
sed -i '/.*aio_cancel_7-1/d' unresolved_list
sed -i '/.*aio_suspend_1-1/d' unresolved_list
cat unresolved_list >> failed_list

# ignore known failures
uname -m | grep -q s390
if [ $? -eq 0 ]; then
    # s390x high steal time can cause higher than expected times
    # it takes for syscalls like nanosleep to complete
    sed -i '/.*timer_getoverrun_2-3/d' failed_list
    sed -i '/.*timer_create_11-1/d' failed_list
    sed -i '/.*timer_gettime_1-3/d' failed_list
fi

failed_no=$(cat failed_list | wc -l)
if [ "$failed_no" -gt 0 ]; then
    SubmitLog logfile.runall
    echo "Failed testcases:" | tee -a $OUTPUTFILE
    cat failed_list | tee -a $OUTPUTFILE
    # if there is failure, submit all logs
    SubmitLog $opt_dir/logfile.conformance-test
    SubmitLog $opt_dir/logfile.functional-test
    SubmitLog $opt_dir/logfile.stress-test
    rstrnt-report-result testcases FAIL 1
else
    echo "All testcases passed." | tee -a $OUTPUTFILE
    rstrnt-report-result testcases PASS
fi

# if testcase on excluded list failed, remove it, so we get core
cp -f grab_corefiles_excluded_bins grab_corefiles_excluded_bins.filtered
for failed_case in $(cat failed_list); do
    failed_case_dir=$(dirname $failed_case)
    failed_case_name="$(basename $failed_case_dir)/$(basename $failed_case)"
    sed -i "/${failed_case_name}[.$]/d" grab_corefiles_excluded_bins.filtered
done

# some testcases send signals which result in corefiles by design
# these are not interesting, unless the testcase failed
echo "Grabbing core files" | tee -a $DEBUGLOG
bash ./grab_corefiles.sh $opt_dir $(pwd)/grab_corefiles_excluded_bins.filtered >> $DEBUGLOG 2>&1
SubmitLog $DEBUGLOG
echo "Submitted $DEBUGLOG" | tee -a $DEBUGLOG

# restore either NTP or chronyd
if [ -n "$tservice" ]; then
    service chronyd start
else
    EnableNTP
fi

exit 0
