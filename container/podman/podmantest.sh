#!/bin/bash
#--------------------------------------------------------------------------------
# Copyright (c) 2021 Red Hat, Inc. All rights reserved. This copyrighted material
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
#
# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

TEST_FAILED=0
ARCH=$(uname -m)

#  Switching root or rootless podmantest
if [[ $(id -u) -eq 0 ]]; then
    echo "Running root podmantest:"
else
    echo "Running rootless podmantest"
fi

if [ -z $1 ]; then
    echo "FAIL: test requires test directory as parameter"
    exit 1
fi
TEST_DIR=$1

# Bug reports required this information.
echo "Podman version:"
podman --version
echo "Podman debug info:"
podman info --debug

# Clear images
podman system prune --all --force && podman rmi --all

for TEST_FILE in ${TEST_DIR}/*.bats; do
    TEST_NAME=$(basename $TEST_FILE)
    TEST_LOG="./${TEST_NAME/bats/log}"
    echo -e "\n[$(date '+%F %T')] $TEST_NAME" | tee "${TEST_LOG}"
    bats $TEST_FILE |& awk --file timestamp.awk | tee -a "${TEST_LOG}"
    # Save a marker if this test failed.
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        TEST_FAILED=1
        cki_upload_log_file ${TEST_LOG}
    fi
done

echo "Test finished"

exit $TEST_FAILED
