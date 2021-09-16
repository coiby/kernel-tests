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
ARCH=$(uname -m)
PODMAN_VERSION=$(podman --version | awk '{print$3}')

function _install_bats ()
{
    curl --retry 5 -LO https://github.com/bats-core/bats-core/archive/v1.1.0.tar.gz
    tar xvf v1.1.0.tar.gz > /dev/null
    ./bats-core-1.1.0/install.sh /usr
    if [ $? -ne 0 ]; then
        echo "FAIL Couldn't install BATS. Aborting test..."
        rstrnt-report-result "${TEST}" WARN
        rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
        exit 1
    fi
}

# there was some fixes in podman tests, that were not available on 3.3.1
if rlTestVersion ${PODMAN_VERSION} '<=' '3.3.1'; then
    COMMIT_HASH=02a0d4b7fb8fe99d012e9c8035a063e903eab5b6

    if [ ! -d podman ]; then
        git clone https://github.com/containers/podman
        if [ $? -ne 0 ]; then
            echo "FAIL to clone podman repo. Aborting test..."
            rstrnt-report-result "${TEST}" WARN
            rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
            exit 1
        fi
        pushd podman
        git checkout ${COMMIT_HASH}
        if [ $? -ne 0 ]; then
            echo "FAIL to checkout ${COMMIT_HASH}. Aborting test..."
            rstrnt-report-result "${TEST}" WARN
            rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
            exit 1
        fi
        popd
    fi
    TEST_DIR="$PWD/podman/test/system"
else
    rpm -q podman-tests
    if [ $? -ne 0 ]; then
        echo "FAIL: podman-tests is not installed. Aborting test..."
        rstrnt-report-result "${TEST}" WARN
        rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
        exit 1
    fi
    TEST_DIR=/usr/share/podman/test/system
fi

# If bats is not install, install it from source
if [ ! -x /usr/bin/bats ]; then
    _install_bats
fi

# NOTE(mhayden): The 'metacopy=on' mount option may be causing issues with
# podman on RHEL 8. It needs to be disabled per BZ 1734799.
if rlTestVersion ${PODMAN_VERSION} '<' '1.4.4'; then
    sed -i 's/,metacopy=on//' /etc/containers/storage.conf || true
    grep ^mountopt /etc/containers/storage.conf || true
fi

# patch 070-builds to make test passing
sed -i -e '/io.buildah.version/d' $TEST_DIR/070-build.bats

# Add container-tools module for rhel8 through Appstreams:
#   rhel8 -> fast rolling stream that closes to upstream/latest
#   1.0, 2.0, ....  -> stable stream for production
if rlIsRHEL '8'; then
    dnf module install -y container-tools:rhel8
fi

if rlIsRHEL; then
    # At least for now, it seems same tests can be skipped for RHEL-8 and RHEL-9
    # In the future it might be better to check podman version instead of release...
    # Skip journal related tests due to: https://bugzilla.redhat.com/show_bug.cgi?id=1972780
    echo "Skipping journald related tests due to BZ1972780..."
    sed -i 's/@test "podman run --log-driver" {/@test "podman run --log-driver" {\n    skip/' ${TEST_DIR}/030-run.bats
    sed -i 's/@test "podman logs - multi journald" {/@test "podman logs - multi journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman logs - since journald" {/@test "podman logs - since journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman logs - until journald" {/@test "podman logs - until journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
fi

if rlTestVersion ${PODMAN_VERSION} '<=' '3.3.1'; then
    # Unsupported tests
    sed -i 's/@test "podman logs - --follow journald" {/@test "podman logs - --follow journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman logs - --follow k8s-file" {/@test "podman logs - --follow k8s-file" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman buildx - basic test" {/@test "podman buildx - basic test" {\n    skip/' ${TEST_DIR}/070-build.bats
    sed -i 's/@test "podman volume import test" {/@test "podman volume import test" {\n    skip/' ${TEST_DIR}/160-volumes.bats
    sed -i 's/@test "podman generate systemd - restart policy" {/@test "podman generate systemd - restart policy" {\n    skip/' ${TEST_DIR}/250-systemd.bats
    sed -i 's/@test "podman pass LISTEN environment " {/@test "podman pass LISTEN environment" {\n    skip/' ${TEST_DIR}/250-systemd.bats
    sed -i 's/@test "podman auto-update - label io.containers.autoupdate=image with rollback" {/@test "podman auto-update - label io.containers.autoupdate=image with rollback" {\n    skip/' ${TEST_DIR}/255-auto-update.bats
    sed -i 's/@test "podman auto-update - label io.containers.autoupdate=local with rollback" {/@test "podman auto-update - label io.containers.autoupdate=local with rollback" {\n    skip/' ${TEST_DIR}/255-auto-update.bats
fi

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
    loginctl enable-linger $PODMANUSER
    # wait few seconds to give time for enable-linger
    sleep 5
    su - podmantest -c "cd `pwd`; bash ./podmantest.sh ${TEST_DIR}"
    TEST_FAILED=$?
    cat /tmp/podmantest-rootless.log >> "${OUTPUTFILE}"
else # Stay with root
    bash ./podmantest.sh ${TEST_DIR}
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
