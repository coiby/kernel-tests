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
    local result=$CKI_PASS;
    pushd "$DMTS_LOCAL" || return 1
    ./dmtest health
    if [[ -e "$DMTS_LOCAL"/LINUX_REPO_UNAVAILABLE ]]; then
      echo "Found LINUX_REPO_UNAVAILABLE file!"
      echo "Skipping tests that require linux repo."
      ./dmtest run --result-set cki_dmtest --and-filters \
      --rx '^/(?!thin/snapshot/(many-snaps-with-changes|try-and-create-duplicates|parallel-io-to-shared-thins))' \
      --rx '^/(?!blk-archive/rolling-snaps)'
    else
      ./dmtest run --result-set cki_dmtest --rx '^/(?!thin/snapshot/parallel-io-to-shared-thins)'
    fi
    output=$(./dmtest list --state FAIL --result-set cki_dmtest | grep -oP '([\w-]+)\s+(?= FAIL)')
    for i in $output; do
        log_file=/tmp/"$i"-"$DATETIME"-FAIL.log
        ./dmtest log --with-dmesg --result-set cki_dmtest "$i" > "$log_file";
        cki_upload_log_file "$log_file"
        result=$CKI_FAIL
    done

    popd || return "$CKI_FAIL"
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
cki_upload_log_file setup.log

runtest
test_status=$?

if [ $test_status -eq "$CKI_FAIL" ] ; then
    rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL
    exit 1
fi

if [ $test_status -eq "$CKI_UNINITIATED" ] ; then
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit "$CKI_STATUS_ABORTED"
fi

exit 0
