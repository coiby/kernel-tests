#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/mce-test/hwpoison
#   Description: HWPoison test (MCA recovery)
#   Author: Evan McNabb <emcnabb@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

# Include helper functions
. /mnt/tests/kernel/mce-test/include/runtest.sh

# --------------- Setup ---------------

# Install test suite
InstallMceTest

# Hugetlbfs
CreateHugepages
MountHugetlbfs

# Prepare system
MountDebugfs
LoadMceInjectMod
LoadHwpoisonInjectMod

# If we've gotten to here setup has passed
report_result "$TEST/setup" "PASS"

# --------------- Start Test  ---------------

# Disable abrt as a work-around for BZ 596782
service abrtd stop

# TARGET_TEST (mce-test directory) set in include file
cd $TARGET_TEST/tsrc

echo "=== Running hard tests:"
rhts-flush
make hard
# Confirm test exited correctly
if [ "$?" -eq 0 ]; then
    echo "Test passed."
    report_result "$TEST/hard" "PASS"
else
    echo "'make hard' command failed, exiting"
    report_result "$TEST/hard" "FAIL"
fi

###############
echo "=== Running soft tests:"
rhts-flush
make soft |tee soft-output.txt

echo -e "\n*** Some failures above are expected since some random pages can't be offlined.
*** See BZ 593844 for details. Test will pass as long as failures are below
*** certain thresholds."
# Note: these threshold values have been somewhat arbitrarily determined. Feel
# free to change them to a more appopriate value.
THRESHOLD=0.25    # 25%

# Increment if any checks fail
FAILED=0

# Confirm soft poison failure count is < $THRESHOLD percent
soft_poison_total=$(grep soft-poison soft-output.txt | awk -F"of total " '{print $2}' | awk '{print $1}')
soft_poison_failed=$(grep soft-poison soft-output.txt | awk -F"failed " '{print $2}' | awk '{print $1}')
result=`echo "($soft_poison_failed/$soft_poison_total) < $THRESHOLD"|bc -l`
if [ "$result" -eq 0 ]; then
    echo "Failure! Above soft_poison failure threshold!"
    FAILED=1
else
    echo "Check passed: soft_poison failures below threshold."
fi

# Confirm unpoison failure count is < $THRESHOLD percent
unpoison_failed_total=$(grep unpoison-failed soft-output.txt | awk -F"of total " '{print $2}' | awk '{print $1}')
unpoison_failed_failed=$(grep unpoison-failed soft-output.txt | awk -F"failed " '{print $2}' | awk '{print $1}')
result=`echo "($unpoison_failed_failed/$unpoison_failed_total) < $THRESHOLD"|bc -l`
if [ "$result" -eq 0 ]; then
    echo "Failure! Above unpoison_failed failure threshold!"
    FAILED=1
else
    echo "Check passed: unpoison_failed failures below threshold."
fi

# Confirm HardwareCorrupted counter from /proc/meminfo has been incremented
poisoned_before=$(grep "poisoned before" soft-output.txt | awk '{print $4}')
poisoned_after=$(grep "poisoned after" soft-output.txt | awk '{print $4}')

if [ "$poisoned_after" -le "$poisoned_before" ]; then
    echo "Failure! poisoned_before is less than or equal to poisoned_after. Possibly didn't even inject?"
    FAILED=1
else
    echo "Check passed: poisoned_after is larger than poisoned_before."
fi

if [ "$FAILED" -gt 0 ]; then
    echo "Test failed!"
    report_result "$TEST/soft" "FAIL"
else
    echo "Test passed."
    report_result "$TEST/soft" "PASS"
fi

# Re-enable abrt as a work-around for BZ 596782
service abrtd start
UmountDebugfs
ResetHugetlbfs
###############

echo "*** End of runtest.sh ***"
