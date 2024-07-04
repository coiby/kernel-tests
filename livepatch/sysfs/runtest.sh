#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/livepatch/sysfs
#   Description: Livepatch sysfs tests
#   Author: Yulia Kopkova <ykopkova@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
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
. ../../general/kpatch/include/lib.sh

TEST="/kernel/livepatch/sysfs"

KLP_SYSFS="/sys/kernel/livepatch"
KLP_MODULE="test_klp_callbacks_demo"
BUSY_MODULE="test_klp_callbacks_busy"
BUILDS_URL="${BUILDS_URL:-}"

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

if is_rhel9 || is_rhel8; then
	dnf_install_modules_internal
	klp_module_file=$(modinfo $KLP_MODULE | head -n 1 | awk '{print $2}')
	busy_module_file=$(modinfo $BUSY_MODULE | head -n 1 | awk '{print $2}')
else
	install_selftests_internal
	rhel10_build_selftests_modules
	klp_module_file="$LIVEPATCH_TEST_MODULES/test_modules/$KLP_MODULE.ko"
	busy_module_file="$LIVEPATCH_TEST_MODULES/test_modules/$BUSY_MODULE.ko"
fi

echo "Trigger livepatch stall transition with $klp_module_file" | tee -a $OUTPUTFILE
insmod $busy_module_file block_transition=Y
insmod $klp_module_file

msg="$KLP_MODULE is enabled"
lsmod | grep $KLP_MODULE && [ $(cat $KLP_SYSFS/$KLP_MODULE/enabled) -eq 1 ] && \
	test_log "$msg" || { test_fail "$msg" && exit 0; }

sleep 15
msg="$KLP_MODULE transition is stalled"
[ $(cat $KLP_SYSFS/$KLP_MODULE/transition) -eq 1 ] && \
	test_log "$msg" || { test_fail "$msg" && exit 0; }

echo 1 > $KLP_SYSFS/$KLP_MODULE/force
for i in $(seq 1 20); do
	sleep 1
	[ $(cat $KLP_SYSFS/$KLP_MODULE/transition) -eq 0 ] && break
done

msg="Transition force finished"
[ $(cat $KLP_SYSFS/$KLP_MODULE/transition) -eq 0 ] && \
	test_pass "$msg ($i sec)" || test_fail "$msg"

msg="$BUSY_MODULE object patched"
[[ ! -e "$KLP_SYSFS/$KLP_MODULE/$BUSY_MODULE/patched" ]] && test_pass "object/patched sysfs entry empty" \
	|| ([ $(cat $KLP_SYSFS/$KLP_MODULE/$BUSY_MODULE/patched) -eq 1 ] && test_pass "$msg" || test_fail "$msg")

echo 0 > $KLP_SYSFS/$KLP_MODULE/enabled
modprobe -r $BUSY_MODULE
rmmod $KLP_MODULE

exit 0
