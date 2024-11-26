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

# Global variables
PODMANUSER=${PODMANUSER:-root}
BATS_DIR=${BATS_DIR:-/usr}
LOG_DIR="/tmp/podmantestlog"
TEST="Podman"
ARCH=$(uname -m)

function _install_bats ()
{
    curl --retry 5 -LO https://github.com/bats-core/bats-core/archive/refs/tags/v1.10.0.tar.gz
    tar xvf v1.10.0.tar.gz > /dev/null
    ./bats-core-1.10.0/install.sh "${BATS_DIR}"
    if [ $? -ne 0 ]; then
        echo "FAIL Couldn't install BATS. Aborting test..."
        rstrnt-report-result "${TEST}" WARN
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
    backed_files=$(find ${TEST_DIR} -iname '*.bak')
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
        # shellcheck disable=SC2294
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

    # Clear images
    run_cmd_user "podman system prune --all --force && podman rmi --all"

    TEST_FILES=$(grep -rE "^# bats test_tags=distro-integration" "$TEST_DIR"/*.bats | cut -d ":" -f 1 | sort -u)
    for TEST_FILE in ${TEST_FILES}; do
        TEST_NAME=$(basename $TEST_FILE)
        TEST_LOG="${LOG_DIR}/${TEST_NAME/bats/log}"
        echo -e "\n[$(date '+%F %T')] $TEST_NAME" | tee "${TEST_LOG}"
        run_cmd_user "bats --filter-tags distro-integration $TEST_FILE" |& awk --file timestamp.awk | tee -a "${TEST_LOG}"
        # Save a marker if this test failed.
        if [[ ${PIPESTATUS[0]} != 0 ]]; then
            TEST_FAILED=1
            if grep -qF "[ rc=124 (** EXPECTED 0 **) ]" ${TEST_LOG}; then
                echo "FAIL: test failed with timeout. Likely infra issue."
                rstrnt-report-result -o "${TEST_LOG}" "${RSTRNT_TASKNAME}/${TEST_NAME}" WARN
                cleanup
                exit 1
            else
                rstrnt-report-result -o "${TEST_LOG}" "${RSTRNT_TASKNAME}/${TEST_NAME}" FAIL
            fi
        else
            rstrnt-report-result -o "${TEST_LOG}" "${RSTRNT_TASKNAME}/${TEST_NAME}" PASS
        fi
    done

    echo "Test finished"
    return $TEST_FAILED
}

rpm -q podman-tests
if [ $? -ne 0 ]; then
    echo "FAIL: podman-tests is not installed. Aborting test..."
    rstrnt-report-result "${TEST}" WARN
    exit 1
fi

TEST_DIR=/usr/share/podman/test/system

# If bats is not install, install it from source

if [[ -e /run/ostree-booted ]];then
   BATS_DIR=/usr/local
fi

if [ ! -x "${BATS_DIR}"/bin/bats ]; then
    _install_bats
fi

# patch 070-builds to make test passing
sed -i -e '/io.buildah.version/d' $TEST_DIR/070-build.bats


rhel_centos_release=$(rpm -E '%rhel')

# Add container-tools module for rhel8 through Appstreams:
#   rhel8 -> fast rolling stream that closes to upstream/latest
#   1.0, 2.0, ....  -> stable stream for production
if [[ "$rhel_centos_release" == "8" ]]; then
    dnf module install -y container-tools:rhel8
fi


if [[ "$rhel_centos_release" == "8" ]] || [[ "$rhel_centos_release" == "9" ]]; then
    # https://github.com/containers/podman/issues/20087
    echo "Skipping selinux-policy tests known to fail: https://github.com/containers/podman/issues/20087"
    sed -i 's/@test "podman selinux: confined container" {/@test "podman selinux: confined container" {\n    skip/' ${TEST_DIR}/410-selinux.bats
    sed -i 's/@test "podman selinux: container with label=disable" {/@test "podman selinux: container with label=disable" {\n    skip/' ${TEST_DIR}/410-selinux.bats
    sed -i 's/@test "podman selinux: privileged container" {/@test "podman selinux: privileged container" {\n    skip/' ${TEST_DIR}/410-selinux.bats
    sed -i 's/@test "podman selinux: pid=host" {/@test "podman selinux: pid=host" {\n    skip/' ${TEST_DIR}/410-selinux.bats
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

# Increase the test timeout in ppc64le as the build tests need longer time to finish
if [ "$ARCH" == "ppc64le" ]; then
        export PODMAN_TIMEOUT=420
fi

run_tests
TEST_FAILED=$?

if [[ ${TEST_FAILED} != 0 ]] ; then
    echo "😭 One or more tests failed."
else
    echo "😎 All tests passed."
fi

cleanup

# If running as restraint job, don't use exit code as failures should be reported as subtest
[[ -v RSTRNT_JOBID ]] || exit "${TEST_FAILED}"
