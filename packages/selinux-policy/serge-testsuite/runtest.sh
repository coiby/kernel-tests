#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/selinux-policy/Sanity/serge-testsuite
#   Description: functional test suite for the LSM-based SELinux security module
#   Author: Milos Malik <mmalik@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

set -ex

git_url=${WRAPPER_GIT_URL:-"https://src.fedoraproject.org/tests/selinux.git"}
git_branch=${WRAPPER_GIT_BRANCH:-"main"}
git_path=${WRAPPER_GIT_PATH:-"kernel/selinux-testsuite"}

TEST="packages/selinux-policy/serge-testsuite"
# Test doesn't run without IPv6
if grep "ipv6.disable=1" /proc/cmdline ; then
    echo "Skip test as system doesn't have IPv6."
    rstrnt-report-result $TEST SKIP
    exit
fi

function __prepare_failed()
{
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
}

trap "__prepare_failed" ERR

test_repo_path=$(readlink -f test-repo)

git clone "$git_url" "test-repo"
cd "test-repo"
git checkout "$git_branch"
git rev-parse --verify "$git_branch"

# shellcheck disable=SC2064
trap "cd /; rm -rf '${test_repo_path}'" EXIT ERR

cd "$git_path"

set +e
./runtest.sh
if [ $? -eq 127 ]; then
    # Aborting task due to infrastructure failure.
    echo "Test finished with infrastructure error."
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
fi
