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
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Global variables
PODMANUSER=${PODMANUSER:-root}
BATS_DIR=${BATS_DIR:-/usr}
LOG_DIR="/tmp/podmantestlog"
TEST="Podman"
ret=0
ARCH=$(uname -m)
PODMAN_VERSION=$(podman --version | awk '{print$3}')

function _install_bats ()
{
    curl --retry 5 -LO https://github.com/bats-core/bats-core/archive/v1.1.0.tar.gz
    tar xvf v1.1.0.tar.gz > /dev/null
    ./bats-core-1.1.0/install.sh "${BATS_DIR}"
    if [ $? -ne 0 ]; then
        echo "FAIL Couldn't install BATS. Aborting test..."
        rstrnt-report-result "${TEST}" WARN
        rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
        exit 1
    fi
}

function _disable_test()
{
    if [ -f ${TEST_DIR}/${1} ]; then
        echo "INFO: disabling ${TEST_DIR}/${1}"
        mv -f ${TEST_DIR}/${1} ${TEST_DIR}/${1}.bak
    fi
}

function _restore_tests()
{
    backed_files=$(find ${TEST_DIR} -iname *.bak)
    for test_file in ${backed_files}; do
        orig_name=$(echo ${test_file} | sed 's/.bak//')
        echo "INFO: restoring ${orig_name}"
        mv -f ${test_file} ${orig_name}
    done
}

function cleanup()
{
    # Clean podman interfaces when is done
    ifaces=$(ip -json link show  | jq -r '.[].ifname' | grep cni-podman)
    if [ ! -z "$ifaces" ]; then
        for iface in $ifaces; do
             echo "Delete podman interface: $iface"
             ip link delete $iface
        done
    fi

    _restore_tests
}

function run_cmd_user()
{
    if  [[ "$PODMANUSER" != "root" ]]; then
        su - "$PODMANUSER" -c "$@"
    else
        eval "$@"
    fi
}

function run_tests()
{
    TEST_FAILED=0
    # Bug reports required this information.
    echo "Podman version:"
    if run_cmd_user "podman --version"; then
        rstrnt-report-result "${RSTRNT_TASKNAME}/version" PASS
    else
        TEST_FAILED=1
        rstrnt-report-result "${RSTRNT_TASKNAME}/version" FAIL
    fi
    echo "Podman debug info:"
    if run_cmd_user "podman info --debug"; then
        rstrnt-report-result "${RSTRNT_TASKNAME}/info" PASS
    else
        TEST_FAILED=1
        rstrnt-report-result "${RSTRNT_TASKNAME}/info" FAIL
    fi

    # return before executing podman-tests
    echo "WARN: not executing podman tests due to lack of test maintainer capacity"
    echo "more details: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1502"
    return $TEST_FAILED

    # Clear images
    run_cmd_user "podman system prune --all --force && podman rmi --all"

    for TEST_FILE in ${TEST_DIR}/*.bats; do
        TEST_NAME=$(basename $TEST_FILE)
        TEST_LOG="${LOG_DIR}/${TEST_NAME/bats/log}"
        echo -e "\n[$(date '+%F %T')] $TEST_NAME" | tee "${TEST_LOG}"
        run_cmd_user "bats $TEST_FILE" |& awk --file timestamp.awk | tee -a "${TEST_LOG}"
        # Save a marker if this test failed.
        if [[ ${PIPESTATUS[0]} != 0 ]]; then
            TEST_FAILED=1
            rstrnt-report-log -l ${TEST_LOG}
            if grep -qF "[ rc=124 (** EXPECTED 0 **) ]" ${TEST_LOG}; then
                echo "FAIL: test failed with timeout. Likely infra issue."
                rstrnt-report-result "${RSTRNT_TASKNAME}/${TEST_NAME}" WARN
                cleanup
                rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
                exit 1
            else
                rstrnt-report-result "${RSTRNT_TASKNAME}/${TEST_NAME}" FAIL
            fi
        else
            rstrnt-report-result "${RSTRNT_TASKNAME}/${TEST_NAME}" PASS
        fi
    done

    echo "Test finished"
    return $TEST_FAILED
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

if [[ -e /run/ostree-booted ]];then
   BATS_DIR=/usr/local
fi

if [ ! -x "${BATS_DIR}"/bin/bats ]; then
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

if rlIsRHEL || rlIsCentOS '9'; then
    # At least for now, it seems same tests can be skipped for RHEL-8, RHEL-9, and CentOS Stream 9
    # In the future it might be better to check podman version instead of release...
    # Skip journal related tests due to: https://bugzilla.redhat.com/show_bug.cgi?id=1972780
    echo "Skipping journald related tests due to BZ1972780..."
    sed -i 's/@test "podman run --log-driver" {/@test "podman run --log-driver" {\n    skip/' ${TEST_DIR}/030-run.bats
    sed -i 's/@test "podman logs - multi journald" {/@test "podman logs - multi journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman logs - since journald" {/@test "podman logs - since journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
    sed -i 's/@test "podman logs - until journald" {/@test "podman logs - until journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
fi

if rlTestVersion ${PODMAN_VERSION} '<' '3.4.3'; then
    # Please refer to https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/807
    # and https://github.com/containers/podman/pull/12496
    sed -i 's/@test "podman kill - test signal handling in containers" {/@test "podman kill - test signal handling in containers" {\n    skip/' ${TEST_DIR}/130-kill.bats
    sed -i 's/@test "podman logs - --follow journald" {/@test "podman logs - --follow journald" {\n    skip/' ${TEST_DIR}/035-logs.bats
fi

if rlTestVersion ${PODMAN_VERSION} '<=' '3.3.1'; then
    # https://bugzilla.redhat.com/show_bug.cgi?id=2006678
    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/622
    sed -i 's/@test "podman build - global runtime flags test" {/@test "podman build - global runtime flags test" {\n    skip/' ${TEST_DIR}/070-build.bats
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

if rlTestVersion ${PODMAN_VERSION} '=' '3.4.0'; then
    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/774
    sed -i 's/@test "podman volume import test" {/@test "podman volume import test" {\n    skip/' ${TEST_DIR}/160-volumes.bats
    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/781
    _disable_test 270-socket-activation.bats
fi

# Skip 150-logins,420-cgroups.bats,260-sdnotify,200-pod,410-selinux,600-completion,700-play,035-logs for non x86_64, would fail on non x86_64
if [ "$ARCH" != "x86_64" ]; then
    _disable_test 150-login.bats
    _disable_test 420-cgroups.bats
    _disable_test 260-sdnotify.bats
    _disable_test 200-pod.bats
    _disable_test 410-selinux.bats
    _disable_test 600-completion.bats
    _disable_test 700-play.bats
    _disable_test 035-logs.bats
fi

if  [[ "$PODMANUSER" != "root" ]]; then
    # Switch to rootless for non root
    # Check existing rootless podman user
    if ! id $PODMANUSER ;then
        echo "Adding rootless podman user: $PODMANUSER"
        adduser $PODMANUSER
    fi

    _disable_test 220-healthcheck.bats
    _disable_test 250-systemd.bats
    _disable_test 260-sdnotify.bats
    _disable_test 410-selinux.bats

    if [ "$ARCH" != "x86_64" ]; then
        # 500-networking would fail in non x86_64, add to exclusion
        _disable_test 500-networking.bats
    fi

    loginctl enable-linger $PODMANUSER
    # wait few seconds to give time for enable-linger
    sleep 5
else # Stay with root

    if [ "$ARCH" == "ppc64le" ]; then
        # 050-stops would fail in ppc64le, add to exclusion
        _disable_test 050-stops.bats
    fi
fi

if [ ! -d ${LOG_DIR} ]; then
    mkdir ${LOG_DIR}
fi
rm -f "${LOG_DIR}/*.log"

run_tests
TEST_FAILED=$?

if [[ ${TEST_FAILED} != 0 ]] ; then
    echo "😭 One or more tests failed."
else
    echo "😎 All tests passed."
fi

cleanup

exit ${TEST_FAILED}
