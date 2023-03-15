#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/mce-test/simple
#   Description: mce-test simple test driver
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

# Prepare system
MountDebugfs
LoadMceInjectMod

# If we've gotten to here setup has passed
report_result "$TEST/setup" "PASS"

# --------------- Start Test  ---------------

rhts-flush
# TARGET_TEST (mce-test directory) set in include/runtest.sh
cd $TARGET_TEST
./drivers/simple/driver.sh simple.conf

if grep -q 'Failed:' results/simple/result
then
    report_result "$TEST/simple-driver" "FAIL"
    tar -cvzf results.tar.gz results/
    tar -cvzf work.tar.gz work/
    rhts_submit_log -S ${RESULT_SERVER} -T ${TESTID} -l results/simple/result
    rhts_submit_log -S ${RESULT_SERVER} -T ${TESTID} -l results.tar.gz
    rhts_submit_log -S ${RESULT_SERVER} -T ${TESTID} -l work.tar.gz
else
    report_result "$TEST/simple-driver" "PASS"
fi

echo "*** End of runtest.sh ***"
