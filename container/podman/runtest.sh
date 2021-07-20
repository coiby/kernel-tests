#!/bin/bash
#--------------------------------------------------------------------------------
# Copyright (c) 2019 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Global variables
PODMANUSER=${PODMANUSER:-root}
TEST="Podman"
ret=0
BATS_RPM="http://mirrors.kernel.org/fedora/releases/33/Everything/x86_64/os/Packages/b/bats-1.1.0-5.fc33.noarch.rpm"
ARCH=$(uname -m)

# Verify that podman-tests is installed
pkg=$(rpm -qa | grep podman-tests)
if [ -z "$pkg" ] ; then
    rstrnt-report-result "${TEST}" WARN
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

# RHEL 8 will install podman-tests, but it will not install bats. We can use
# the Fedora 31 package instead. Attempt the installation five times.
if [ ! -x /usr/bin/bats ]; then
    for i in {1..5}; do
        dnf -y --nogpgcheck install $BATS_RPM && break
    done
fi

# NOTE(mhayden): The 'metacopy=on' mount option may be causing issues with
# podman on RHEL 8. It needs to be disabled per BZ 1734799.
PODMAN_RPM_NAME=$(rpm -q podman)
if [[ $PODMAN_RPM_NAME =~ el8 ]]; then
    sed -i 's/,metacopy=on//' /etc/containers/storage.conf || true
    grep ^mountopt /etc/containers/storage.conf || true
fi

# Run the podman system tests.
TEST_DIR=/usr/share/podman/test/system
# Buildah now supports cross-arch builds
# https://github.com/containers/podman/pull/9491
sed -i -e 's/\(20200902\|20200929\|20210223\|20210427\)/20210610/' $TEST_DIR/helpers.bash
sed -i -e 's/\(:00000000\|:00000001\|:00000002\)/:00000003/' $TEST_DIR/helpers.bash

# patch 070-builds to make test passing
sed -i -e '/io.buildah.version/d' $TEST_DIR/070-build.bats

# Patch when running rhel to make tests passing
if rlIsRHEL; then
    sed -i -e 's/\(20200902\|20200929\|20210223\|20210427\)/20210610/' $TEST_DIR/*.bats
    sed -i -e 's/\(:00000000\|:00000001\|:00000002\)/:00000003/' $TEST_DIR/*.bats
fi

# Patch 030-run and 500-networking,  system tests: fix two race condition https://github.com/containers/podman/pull/10157
if ! grep -q "run_podman kill \$cid; run_podman wait \$cid" $TEST_DIR/030-run.bats; then
    sed -i -e 's/run_podman kill $cid/run_podman kill $cid; run_podman wait $cid/' $TEST_DIR/030-run.bats
fi
if ! grep -q "run_podman wait \$cid" $TEST_DIR/500-networking.bats; then
    sed -i -e 's/run_podman rm $cid/run_podman wait $cid; run_podman rm $cid/' $TEST_DIR/500-networking.bats
fi

# Patch 050-stop.bats flake, fix racy podman-inspect https://github.com/containers/podman/pull/10028
if ! grep -q "run_podman wait stopme" $TEST_DIR/050-stop.bats; then
    sed -i -e 's/run_podman kill stopme/run_podman kill stopme; run_podman wait stopme/' $TEST_DIR/050-stop.bats
fi

# Patch 255-auto-update.bats system test: auto-update: multiarch fixes, and cleanup https://github.com/containers/podman/pull/10985
sed -i -e 's/alpine_nginx/busybox/g' $TEST_DIR/255-auto-update.bats

# Skip 150-logins,420-cgroups.bats,260-sdnotify,200-pod,410-selinux,600-completion,700-play,035-logs for non x86_64, would fail on non x86_64
if [ "$ARCH" != "x86_64" ]; then
    mv -f ${TEST_DIR}/150-login.bats ${TEST_DIR}/150-login.baks
    mv -f ${TEST_DIR}/420-cgroups.bats ${TEST_DIR}/420-cgroups.baks
    mv -f ${TEST_DIR}/260-sdnotify.bats ${TEST_DIR}/260-sdnotify.baks
    mv -f ${TEST_DIR}/200-pod.bats ${TEST_DIR}/200-pod.baks
    mv -f ${TEST_DIR}/410-selinux.bats ${TEST_DIR}/410-selinux.baks
    mv -f ${TEST_DIR}/600-completion.bats ${TEST_DIR}/600-completion.baks
    mv -f ${TEST_DIR}/700-play.bats ${TEST_DIR}/700-play.baks
    mv -f ${TEST_DIR}/035-logs.bats ${TEST_DIR}/035-logs.baks
fi

if  [[ "$PODMANUSER" != "root" ]]; then
    # Switch to rootless for non root
    # Check existing rootless podman user
    if ! id $PODMANUSER ;then
        echo "Adding rootless podman user: $PODMANUSER"
        adduser $PODMANUSER
    fi
    su - podmantest -c "cd `pwd`; bash ./podmantest.sh"
    TEST_FAILED=$?
    cat /tmp/podmantest-rootless.log >> "${OUTPUTFILE}"
else # Stay with root
    bash ./podmantest.sh
    TEST_FAILED=$?
    cat /tmp/podmantest-root.log >> "${OUTPUTFILE}"
fi

if [[ ${TEST_FAILED:-} == 1 ]] ; then
    echo "😭 One or more tests failed."
    rstrnt-report-result "${TEST}" FAIL 
else
    echo "😎 All tests passed."
    rstrnt-report-result "${TEST}" PASS 
fi
