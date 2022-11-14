#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/mce-test/extended
#   Description: mce-test extended tests
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

# Install test suites
InstallMceInject
InstallMceTest
InstallPageTypes
InstallLTP

# Prepare system
MountDebugfs
LoadMceInjectMod
LoadHwpoisonInjectMod

echo "Creating loopback partition for mce-test stress test"
if [ ! -f /image.out ]; then dd if=/dev/zero of=/image.out bs=1024 count=5000000; fi
LOOPDEV=`losetup -f`
losetup $LOOPDEV /image.out
if [ "$?" -ne 0 ]; then
    echo "Unable to create loopback partition, exiting"
    report_result "$TEST/setup" "FAIL"
    exit 0
fi

report_result "$TEST/setup" "PASS"

# --------------- Start Test  ---------------

# TARGET_TEST (mce-test directory) set in Makefile
cd $TARGET_TEST/stress
# Remove any existing log and result files
rm -rf log result
make

# Fix incorrect variable path, reported bug upstream. Can eventually remove.
sed -i "s/tmp=\$g_testdir\/fs_metadata/tmp=\$g_rootdir\/\$g_testdir\/fs_metadata/" hwpoison.sh

RunTest()
{
    name=$1
    option=$2
    ./hwpoison.sh -d $LOOPDEV -C 4 -F -t 300 $option
    failures=`grep "task-groups report failures" result/hwpoison.result |cut -f2 -d" "`
    if [ "$failures" -eq 0 ]; then
        echo "PASS: no failures in logs"
        report_result "$TEST/stress/$name" "PASS"
    else
        echo "FAIL: encountered $failures failures"
        report_result "$TEST/stress/$name" "FAIL"
    fi
    mkdir results-$name
    mv log result results-$name
    tar -zcvf results-$name.tar.gz results-$name
    rhts_submit_log -S ${RESULT_SERVER} -T ${TESTID} -l results-$name.tar.gz
}

echo -e "\n\n==== Running hwpoison.sh with -S (test soft page offline) ===="
RunTest "soft" "-S"

echo -e "\n\n==== Running hwpoison.sh with -M (run page_poisoning test thru madvise syscall) ===="
RunTest "madvise" "-M"

# APEI/EINJ currently not supported in RHEL6, planned for 6.1 (BZ 554932).
# echo -e "\n\n==== Running hwpoison.sh with -A (use APEI to inject error) ===="
# RunTest "apei" "-A"

losetup -d $LOOPDEV
echo "*** End of runtest.sh ***"
