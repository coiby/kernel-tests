#!/bin/bash
#
# Copyright (c) 2020-2021 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#


source ../../../cki_lib/libcki.sh
source ./setup.sh

TMPDIR=/var/tmp/$(date +"%Y%m%d%H%M%S")

LOG_DIR=$(get_test_log_dir)

function upload_log_files
{
    typeset log_file=""
    typeset log_files=$(find $LOG_DIR -name "*.log")
    for log_file in $(echo $log_files); do
        cki_upload_log_file $log_file
    done
}

function runtest
{
    # XXX: Never use cki_run_cmd_xxx() wrapper, or it hangs
    source /etc/profile.d/rvm.sh || return 1

    pushd $DMTS_LOCAL

    # Save list of tests
    # the test cases names have '^    ' before their name
    dmtest list --suite thin-provisioning -t BasicTests | grep -E '^    ' > test.list
    if (( $? != 0 )); then
        echo "FAIL: couldn't get the list of tests"
        upload_log_files
        return $CKI_UNINITIATED
    fi

    failed=0
    while read testcase; do
        echo "Running: dmtest run --suite thin-provisioning -n $testcase"
        dmtest run --suite thin-provisioning -n $testcase
        if (( $? != 0 )); then
            # save information about running devices
            # this can help debug failures like when it is unable to remove a device
            # ex: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/538
            lsof > $LOG_DIR/BasicTests_${testcase}_lsof.log
            ps -aux > $LOG_DIR/BasicTests_${testcase}_ps_aux.log
            dmsetup ls > $LOG_DIR/BasicTests_${testcase}_dmsetup_ls.log
            dmsetup info > $LOG_DIR/BasicTests_${testcase}_dmsetup_info.log
            failed=1
        fi
    done < "test.list"
    if (( $failed != 0 )); then
        upload_log_files
        return $CKI_FAIL
    fi

    popd
    upload_log_files
    return $CKI_PASS
}

function startup
{
    # shellcheck disable=SC2174
    [[ ! -d $TMPDIR ]] && mkdir -p -m 0755 $TMPDIR
    echo "INFO: Going to install testsuite"
    ts_setup || return $?
    return $CKI_PASS
}

function cleanup
{
    rm -rf $TMPDIR
    return $CKI_PASS
}

if ! startup &> setup.log ; then
    cat setup.log
    echo "Aborting test as it failed to setup test suite."
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
fi

echo "INFO: testsuite installed successfully. More information on setup.log"
cki_upload_log_file setup.log

runtest
test_status=$?

cleanup

if [ $test_status -eq $CKI_FAIL ] ; then
    rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL
    exit 0
fi

if [ $test_status -eq $CKI_UNINITIATED ] ; then
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
fi

exit 0
