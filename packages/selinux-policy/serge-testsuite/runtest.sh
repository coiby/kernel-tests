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

test_repo_path=$(readlink -f test-repo)

git clone "$git_url" "test-repo"

# shellcheck disable=SC2064
trap "cd /; rm -rf '${test_repo_path}'" EXIT ERR

cd "test-repo"
git checkout "$git_branch" || __prepare_failed
git rev-parse --verify "$git_branch" || __prepare_failed

cd "$git_path" || __prepare_failed

set +e
# NOTE: the timeout needs to be sufficiently lower than
# max_duration_seconds in kpet-db.
timeout -s KILL 2400 ./runtest.sh
test_exit_code=$?

# Clean up stuff that could cause errors later; errors are ignored.
if [ -e "/root/selinux-testsuite" ]; then
    for script in /root/selinux-testsuite/tests/*/*-flush; do
        if [ "$(head -n 1 "$script")" = "#!/bin/sh" ]; then
            sh "$script"
        elif command -v nft &>/dev/null; then
            nft -f "$script"
        fi
    done
    make -C "/root/selinux-testsuite/policy" unload
fi

case $test_exit_code in
127)
    # Aborting task due to infrastructure failure.
    echo "Test finished with infrastructure error."
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
    ;;
124)
    # Aborting task due to timeout.
    echo "Test timed out."
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    exit 0
    ;;
esac
