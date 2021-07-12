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
TEST_DIR=/usr/share/podman/test/system
OUTPUTFILE=""
ARCH=$(uname -m)

# Exclude tests that would fail runnning rootless
excludeTests="220-healthcheck 250-systemd 260-sdnotify 410-selinux"

#  Switching root or rootless podmantest
if [[ $(id -u) -eq 0 ]]; then 
    OUTPUTFILE=/tmp/podmantest-root.log
    > $OUTPUTFILE
    echo "Running root podmantest:" | tee -a "${OUTPUTFILE}"
    excludeTests=""
    if [ "$ARCH" == "ppc64le" ]; then
        # 050-stops would fail in ppc64le, add to exclusion
        excludeTests="050-stops"
    fi

    
else
    OUTPUTFILE=/tmp/podmantest-rootless.log
    > $OUTPUTFILE
    echo "Running rootless podmantest" | tee -a "${OUTPUTFILE}"
    if [ "$ARCH" != "x86_64" ]; then
        # 500-networking would fail in non x86_64, add to exclusion
        excludeTests="${excludeTests} 500-networking"
    fi
fi

# Bug reports required this information.
echo "Podman version:" | tee -a "${OUTPUTFILE}"
podman --version | tee -a "${OUTPUTFILE}"
echo "Podman debug info:" | tee -a "${OUTPUTFILE}"
podman info --debug | tee -a "${OUTPUTFILE}"

# Clear images
podman system prune --all --force && podman rmi --all

for TEST_FILE in ${TEST_DIR}/*.bats; do
    excFound=false
    for excTest in $excludeTests; do
        if [[ "$(basename $TEST_FILE .bats)" == "$excTest" ]]; then
            excFound=true
            break   
        fi
    done
    if  $excFound; then
        continue
    fi

    echo -e "\n📊  $(basename $TEST_FILE):"   | tee -a "${OUTPUTFILE}"
    bats $TEST_FILE | tee -a "${OUTPUTFILE}"
    # Save a marker if this test failed.
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        TEST_FAILED=1
    fi
done

echo "Test finished" | tee -a "${OUTPUTFILE}"

exit $TEST_FAILED
