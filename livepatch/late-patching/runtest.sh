#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/livepatch/late-patching
#   Description: Livepatch late kernel module patching test
#   Author: Yulia Kopkova <ykopkova@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh

TEST="/kernel/livepatch/late-patching"

KLP_SYSFS="/sys/kernel/livepatch"
KLP_MODULE="test_klp_late_patching"
TARGET_MODULE="test_module_late_patching"

DMESG_SAVED=$(mktemp /tmp/dmesg-XXXXXX)
dmesg > $DMESG_SAVED

knvr=$(uname -r)

yum install -y gcc kernel-devel-${knvr%.*} elfutils-libelf-devel

test_fail()
{
	echo -e ":: [  FAIL  ] :: $1" | tee -a $OUTPUTFILE
	rstrnt-report-result $TEST "FAIL" 1
}

test_log()
{
	echo -e ":: [  LOG  ] :: $1" | tee -a $OUTPUTFILE
}

test_pass()
{
	echo -e ":: [  PASS  ] :: $1" | tee -a $OUTPUTFILE
	rstrnt-report-result $TEST "PASS" 0
}

msg="Build $TARGET_MODULE and $KLP_MODULE modules"
pushd source
	make || test_log "$msg"
popd

echo "Trigger late module patching" | tee -a $OUTPUTFILE
insmod source/$KLP_MODULE.ko
msg="$KLP_MODULE is enabled"
lsmod | grep $KLP_MODULE && [ $(cat $KLP_SYSFS/$KLP_MODULE/enabled) -eq 1 ] && \
	test_log "$msg" || { test_fail "$msg" && exit 0; }

sleep 15
insmod source/$TARGET_MODULE.ko
msg="$TARGET_MODULE is loaded"
lsmod | grep $TARGET_MODULE &&  \
	test_log "$msg" || { test_fail "$msg" && exit 0; }

msg="Target function is patched"
dmesg | comm --nocheck-order -13 "$DMESG_SAVED" - | grep -e 'livepatched' && \
	test_pass "$msg" || { test_fail "$msg" && exit 0; }

echo 0 > $KLP_SYSFS/$KLP_MODULE/enabled

rmmod $TARGET_MODULE
rmmod $KLP_MODULE
rm -f $DMESG_SAVED

exit 0
