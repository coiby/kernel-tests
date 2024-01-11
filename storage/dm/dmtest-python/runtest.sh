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

# shellcheck source=/dev/null
source ../../../cki_lib/libcki.sh
source ./setup.sh
export PATH="$PATH":~/.cargo/bin

DATETIME=$(date +"%Y%m%d%H%M%S")

function runtest
{
    pushd "$DMTS_LOCAL" || return 1
    ./dmtest health
    if [[ -e "$DMTS_LOCAL"/LINUX_REPO_UNAVAILABLE ]]; then
      echo "Found LINUX_REPO_UNAVAILABLE file!"
      echo "Skipping tests that require linux repo."
      ./dmtest run --result-set cki_dmtest --and-filters \
      --rx '^/(?!thin/snapshot/(many-snaps-with-changes|try-and-create-duplicates|parallel-io-to-shared-thins))' \
      --rx '^/(?!blk-archive/rolling-snaps)' --rx '^/(?!thin/fs-bench)'
    else
      ./dmtest run --result-set cki_dmtest --and-filters \
      --rx '^/(?!thin/snapshot/parallel-io-to-shared-thins)' --rx '^/(?!thin/fs-bench/)'
    fi
}

function report_results
{
    local result=$CKI_PASS;
    output=$(./dmtest list --state FAIL --result-set cki_dmtest | grep -oP '([\w-]+)\s+(?= FAIL)')
    for i in $output; do
        log_file=/tmp/"$i"-"$DATETIME"-FAIL.log
        ./dmtest log --with-dmesg --result-set cki_dmtest "$i" > "$log_file";
        result=$CKI_FAIL
        # report resuls as subtests if running with restraint
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result -o "$log_file" "${i}" FAIL
    done

    popd || return "$CKI_FAIL"
    # Only report general results in case of pass, if there are failures
    # they are reported already individually as restraint subtests
    if [[ "$result" == "$CKI_PASS" ]]; then
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "Test" PASS
    fi
    return "$result"
}

function startup
{
    echo "INFO: Installing testsuite"
    ts_setup || return $?
    return "$CKI_PASS"
}

if ! startup &> setup.log ; then
    cat setup.log
    echo "Aborting test as it failed to setup test suite."
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit "$CKI_STATUS_ABORTED"
fi

echo "INFO: testsuite installed successfully. More information on setup.log"
[[ -n $RSTRNT_TASKID ]] && rstrnt-report-result -o setup.log "Setup" PASS

runtest
report_results
test_status=$?

# if running as restraint job, the test result is already reported as subtests
# don't exit with values different of 0. Otherwise, restraint reports it as a separate subtest
if [ $test_status -eq "$CKI_FAIL" ] ; then
    # exit with error in case it doesn't run as restraint
    [[ -n $RSTRNT_TASKID ]] || exit 1
fi

if [ $test_status -eq "$CKI_UNINITIATED" ] ; then
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit "$CKI_STATUS_ABORTED"
fi

