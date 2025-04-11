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

export TEST="watchdog/hw-generic"

# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1

# Status file to indicate where we are in the test (after reboot)
TEST_STATUS=/var/tmp/watchdog.status
touch "$TEST_STATUS"

# File to backup/restore bootorder
FILE=/var/tmp/watchdog_boot_order

efi_save()
{
	order=$(efibootmgr | awk '/BootOrder/ {print $2}')
	curr=$(efibootmgr | awk '/BootCurrent/ {print $2}')
	first=$(echo $order | cut -d ',' -f 1 )
	if [ "$first" = "$curr" ]; then
		rlLog "SAVE: boot order is *already* correct"
		return
	fi
	rlLog "SAVE BootOrder"
	new="$curr,$order"
	efibootmgr -o "$new"
	echo "$order" > $FILE
	sync;sync # make sure we save the file
}

efi_restore()
{
	if [ ! -e $FILE ]; then
		rlLog "RESTORE: boot order is correct"
		return
	fi
	order=$(cat $FILE)
	rlLog "RESTORE BootOrder"
	efibootmgr -o "$order"
	if [ $? -ne 0 ]; then
		rlLog "RESTORE Failed! Please investigate to avoid an incorrect boot order"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rlPhaseEnd
		rlJournalEnd
		exit 0
	fi
	rm $FILE
	sync;sync
}


efi_set()
{
	if [[ "$1" != "save" ]] && [[ "$1" != "restore" ]]; then
		rlLog "Invalid command: $1"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rlPhaseEnd
		rlJournalEnd
		exit 0
	fi

	[ "$1" = "save" ] && efi_save || efi_restore
}

chk_support() {
	# Return if we've already executed this function
	if grep -q chk_support "$TEST_STATUS" ; then
		return 0
	fi

	rlLog "Checking Hardware Support"

	# Check that either iTCO or wdat is enabled in the logs
	rlLog "Related dmesg output:"
	egrep -i 'itco|wdat' /var/log/messages || rlLog "*** Warning, no related dmesg output! ***"

	rlLog "Checking that /dev/watchdog exists:"
	if [ -c /dev/watchdog ]; then
		rlLog "/dev/watchdog exists"
		ls -l /dev/watchdog
	else
		rlLog "/dev/watchdog does not exist! Skipping test and existing !"
		rstrnt-report-result $TEST SKIP
		rlPhaseEnd
		rlJournalEnd
		exit 0
	fi

	# Compile watchdog-simple test
	rlLog "Checking that watchdog-simple.c compiled successfully:"
	gcc -o watchdog-simple watchdog-simple.c
	if [ ! -x watchdog-simple ] ; then
		rlLog "Failed to build tests, exiting!"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rlPhaseEnd
		rlJournalEnd
		exit 0
	else
		rlLog "Compiled successfully."
	fi

	# Compile watchdog-set-custom-timeout test
	rlLog "Checking that watchdog-set-custom-timeout.c compiled successfully:"
	gcc -o watchdog-set-custom-timeout watchdog-set-custom-timeout.c
	if [ ! -x watchdog-set-custom-timeout ] ; then
		rlLog "Failed to build tests, exiting!"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rlPhaseEnd
		rlJournalEnd
		exit 0
	else
		rlLog "Compiled successfully."
	fi

	echo chk_support >> "$TEST_STATUS"
	rstrnt-report-result $TEST/supported PASS
}

cleanup() {
	rlLog 'Remove status file'
	rm -f "$TEST_STATUS"
}

disable_wdt_test() {
	# Check if we've already executed this function. If so, this indicates the
	# the system rebooted (almost surely due to the watchdog). Report as PASS.
	if grep -q disable_wdt_test "$TEST_STATUS" ; then
		rlLog "Disabling watchdog successfully triggered a reboot!"
		rstrnt-report-result $TEST/disable_wdt_test PASS
		return 0
	fi
	# Record we've run the test so on reboot we don't run it again
	echo disable_wdt_test >> "$TEST_STATUS"

	# Start watchdog "daemon" in the background (which writes 1's into
	# /dev/watchdog and keeps the box up). After several seconds, kill
	# the program which should then cause the box to reboot.
	rlLog "Disabling writes to /dev/watchdog... System should reboot in 60 seconds"
	sync;sync
	sleep 3
	./watchdog-simple &
	sleep 5
	killall watchdog-simple
	rlLog "Inform tmt that we're rebooting using rstrnt-reboot with a custom non-reboot command."
	rstrnt-reboot -c "echo 'reboot using watchdog'"
	sleep 65
	# If we get here it didn't reboot, so report as FAIL
	rlLog "The system didn't reboot, reporting FAIL!"
	rstrnt-report-result $TEST/disable_wdt_test FAIL
	return 1
}

disable_wdt_test_custom_timeout() {
	# Check if we've already executed this function. If so, this indicates the
	# the system rebooted (almost surely due to the watchdog). Report as PASS.
	if grep -q disable_wdt_test_custom_timeout "$TEST_STATUS" ; then
		rlLog "Disabling watchdog with custom timeout successfully triggered a reboot!"
		rstrnt-report-result $TEST/disable_wdt_test PASS
		return 0
	fi
	# Record we've run the test so on reboot we don't run it again
	echo disable_wdt_test_custom_timeout >> "$TEST_STATUS"

	# Start watchdog "daemon" in the background (which writes 1's into
	# /dev/watchdog and keeps the box up). After several seconds, kill
	# the program which should then cause the box to reboot.
	rlLog "Disabling writes to /dev/watchdog... System should reboot in 120 seconds"
	sync;sync
	sleep 3
	./watchdog-set-custom-timeout
	./watchdog-simple &
	sleep 5
	killall watchdog-simple
	rlLog "Inform tmt that we're rebooting using rstrnt-reboot with a custom non-reboot command."
	rstrnt-reboot -c "echo 'reboot using watchdog with custom timeout'"
	sleep 125
	# If we get here it didn't reboot, so report as FAIL
	rlLog "The system didn't reboot, reporting FAIL!"
	rstrnt-report-result $TEST/disable_wdt_test FAIL
	return 1
}

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel
		rlRun chk_support
		# Set the boot order correctly for UEFI systems
		if efibootmgr; then
			if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
				rlLog "Setting the BootOrder correcty for UEFI system"
				rlLog "Original BootOrder:"
				rlRun efibootmgr
				rlRun "efi_set save"
			fi;
		else
			rlLog "Not a UEFI system. Skipping UEFI boot order setup."
		fi
	rlPhaseEnd
	rlPhaseStartTest "Trigger watchdog reboot"
		rlRun disable_wdt_test
	rlPhaseEnd
	rlPhaseStartTest "Trigger watchdog reboot with custom timeout"
		rlRun disable_wdt_test_custom_timeout
	rlPhaseEnd
	rlPhaseStartCleanup
		rlRun cleanup
		if efibootmgr; then
			rlLog "Restoring the BootOrder correcty for UEFI system"
			rlRun "efi_set restore"
		else
			rlLog "Not a UEFI system. Skipping UEFI boot order restore."
		fi;
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
