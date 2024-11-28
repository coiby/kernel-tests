#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc. All rights reserved.
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

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST="misc/leds_gpio"
brightness_path=/sys/class/leds/green\:indicator-7/brightness

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel
	rlPhaseEnd
	rlPhaseStartTest "Test module is loaded"
		rlAssertGrep "leds_gpio" /proc/modules
	rlPhaseEnd
	rlPhaseStartTest "Test brightness adjustment"
		rlRun "original_value=$(cat $brightness_path)"
		# shellcheck disable=SC2154
		rlLog "Original brightness is $original_value"
		rlRun "echo 1 > $brightness_path"
		rlRun "new_value=$(cat $brightness_path)"
		# shellcheck disable=SC2154
		rlAssertEquals "Assert brightness can be written." $new_value 1
		rlRun "echo $original_value > $brightness_path"
		rlRun "new_value=$(cat $brightness_path)"
		rlAssertEquals "Assert brightness was restored." $new_value $original_value
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
