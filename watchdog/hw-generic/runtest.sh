#!/bin/sh
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/watchdog/hw-generic
#   Description: Confirm hardware watchdog exists and is functional. Disable the watchdog and
#   make sure system reboots as expected.
#   Author: Evan McNabb <emcnabb@redhat.com>
#   Author: William Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 3.
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

TEST="watchdog/hw-generic"

# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1

# Status file to indicate where we are in the test (after reboot)
TEST_STATUS=/var/tmp/watchdog.status
touch "$TEST_STATUS"
# File to backup/restore bootorder
FILE=/tmp/watchdog_boot_order

efi_save()
{
    [ -e $FILE ] && echo "error: back to back save" && exit
    order=$(efibootmgr | grep BootOrder | cut -d : -f 2)
    echo $order > $FILE
    curr=$(efibootmgr | grep BootCurrent | cut -d : -f 2)
    echo -e "\nSAVE" | tee -a ${OUTPUTFILE}
    efibootmgr -o $curr
    echo
}

efi_restore()
{
    [ ! -e $FILE ] && echo "Error: save data is missing" && exit
    order=$(cat $FILE)
    echo -e "\nRESTORE" | tee -a ${OUTPUTFILE}
    efibootmgr -o $order
    echo
    rm $FILE
}

efi_set()
{
    if [[ "$1" != "save" ]] && [[ "$1" != "restore" ]]; then
		echo "Invalid command: $1" | tee -a ${OUTPUTFILE}
		rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    fi

    [ "$1" = "save" ] && efi_save || efi_restore
}

chk_support() {
	# Return if we've already executed this function
	if `grep -q chk_support "$TEST_STATUS"` ; then
		return 0
	fi

	echo -e "\n========== Checking Hardware Support ============" | tee -a ${OUTPUTFILE}

	# Check that either iTCO or wdat is enabled in the logs
	echo -e "\n== Related dmesg output:" | tee -a ${OUTPUTFILE}
	egrep -i 'itco|wdat' /var/log/messages || echo "*** Warning, no related dmesg output! ***" | tee -a ${OUTPUTFILE}

	echo -e "\n== Checking that /dev/watchdog exists:" | tee -a ${OUTPUTFILE}
	if [ -c /dev/watchdog ]; then
		echo "/dev/watchdog exists" | tee -a ${OUTPUTFILE}
		ls -l /dev/watchdog
	else
		echo "/dev/watchdog does not exist! Skipping test and existing !" | tee -a ${OUTPUTFILE}
		rstrnt-report-result $TEST SKIP
		exit 0
	fi

	# Compile watchdog-simple test
	echo -e "\n== Checking that watchdog-simple.c compiled successfully:" | tee -a ${OUTPUTFILE}
	gcc -o watchdog-simple watchdog-simple.c
	if [ ! -x watchdog-simple ] ; then
		echo "Failed to build tests, exiting!" | tee -a ${OUTPUTFILE}
		rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
	else
		echo "Compiled successfully." | tee -a ${OUTPUTFILE}
	fi

	echo chk_support >> "$TEST_STATUS"
	rstrnt-report-result $TEST/supported PASS
}

cleanup() {
	echo -e "\n========== Clean up =============================" | tee -a ${OUTPUTFILE}
	echo 'Remove status file' | tee -a ${OUTPUTFILE}
	rm -f "$TEST_STATUS"
}

disable_wdt_test() {
	echo -e "\n========== Trigger watchdog reboot ============" | tee -a ${OUTPUTFILE}

	# Check if we've already executed this function. If so, this indicates the
	# the system rebooted (almost surely due to the watchdog). Report as PASS.
	if grep -q disable_wdt_test "$TEST_STATUS" ; then
		echo "== Disabling watchdog successfully triggered a reboot:" | tee -a ${OUTPUTFILE}
		rstrnt-report-result $TEST/disable_wdt_test PASS
		return 0
	fi
	# Record we've run the test so on reboot we don't run it again
	echo disable_wdt_test >> "$TEST_STATUS"

	# Start watchdog "daemon" in the background (which writes 1's into
	# /dev/watchdog and keeps the box up). After several seconds, kill
	# the program which should then cause the box to reboot.
	echo "Disabling writes to /dev/watchdog... System should reboot in 30 - 60 seconds" | tee -a ${OUTPUTFILE}
	sync;sync
	sleep 3
	./watchdog-simple &
	sleep 5
	killall watchdog-simple
	sync  # Write data to disk before the system does its hard reset

	# If we get here it didn't reboot, so report as FAIL
	sleep 65
	echo "The system didn't reboot, reporting FAIL!" | tee -a ${OUTPUTFILE}
	rstrnt-report-result $TEST/disable_wdt_test FAIL
}

chk_support
# Set the boot order correctly for UEFI systems
which efibootmgr &> /dev/null
if [ $? -eq 0 ]; then
	if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
		echo -e "\n========== Setting the BootOrder correcty for UEFI system ============" | tee -a ${OUTPUTFILE}
		echo "== Original BootOrder:" | tee -a ${OUTPUTFILE}
		efibootmgr
		efi_set save
	else
		echo -e "\n========== Restoring the BootOrder correcty for UEFI system ============" | tee -a ${OUTPUTFILE}
		efi_set restore
	fi
fi
disable_wdt_test
cleanup
