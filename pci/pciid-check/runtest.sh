#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/pci/pciid-check
#   Description: Confirm PCI IDs are updated on system
#   Author: William R. Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc. All rights reserved.
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

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

result=PASS

# Backup original pci-ids file
cp -af /usr/share/hwdata/pci.ids /usr/share/hwdata/pci.ids.bak

# Check if there are unknown PCI ID strings
check_ids() {
    version=$1

    COUNT=`lspci |grep -c "Unknown device"`
    if [ $COUNT -eq 0 ]; then
        echo -e "\n==== PCI ID list correct"
        report_result "$TEST/$version" "PASS"
    else
        echo -e "\n==== Missing PCI IDs!"
        echo "Unknown devices are: "; lspci |grep "Unknown device"
        report_result "$TEST/$version" "FAIL"
        result=FAIL
    fi
}

# Do lspci sanity check
OUTPUT=`lspci`
if [ $? -ne 0 ]; then
        echo "lspci command failed to execute correctly!"
        report_result "$TEST" FAIL
        exit 1
elif [ -z "$OUTPUT" ]; then
        echo "lspci returned nothing!" # Note, this is vaild on some systems such as some PPC64 lpars
        report_result "$TEST" WARN
        exit 1
fi

echo -e "\n==== lspci output with default pci-ids file: "
lspci

echo -e "\n==== Checking default pci-ids file..."
check_ids default

echo -e "\n==== Fetching upstream pci-ids file..."
# Workaround for https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1875
rlRun "update-pciids" 0-255
ret=$?
if (( ret != 0 )); then
    rlLog "Aborting test. Failed to fetch pci-ids. This is an issue with update-pciids"
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit 1
fi

echo -e "\n==== lspci output with upstream pci-ids file: "; lspci
echo -e "\n==== Checking upstream pci-ids file..."
check_ids upstream

# Restore original pci-ids file
cp -af /usr/share/hwdata/pci.ids.bak /usr/share/hwdata/pci.ids

report_result "$TEST" "$result"

echo "*** End of runtest.sh ***"
