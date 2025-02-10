#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: cover memory-failure.c with upstream mce-test
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

. powerpc.sh

function check_hwpoison_support()
{
	grep -E 'CONFIG_HWPOISON_INJECT=[ym]' /boot/config-$(uname -r)
}

function check_mce_support()
{
	grep -E 'CONFIG_MEMORY_FAILURE=[y|m]' /boot/config-$(uname -r)
}

function test_setup()
{
	rlRun "rm -rf mce-test" 0 "Cleanup mce-test if exists"
	rlRun "git clone git://git.kernel.org/pub/scm/utils/cpu/mce/mce-test.git"
	rlAssertExists "mce-test" || rlDie "Failed to fetch mce-test!"
	pushd mce-test &> /dev/null
	rlRun "make & make install"
	popd

	rlRun "git clone git://git.kernel.org/pub/scm/utils/cpu/mce/mce-inject.git"
	rlAssertExists "mce-inject" || rlDie "Failed to fetch mce-inject!"
	pushd mce-inject &> /dev/null
	rlRun "make && make install"
	popd

	if uname -m | grep x86_64; then
		if ! rlRun "yum -y install mcelog"; then
	        	rlDie "Failed to install mcelog!"
		fi
	fi

	# skip powerpc as the dedicated branch looks to be obsolete upstream
	# uname -m | grep ppc64le && ppc64le_setup
}

# Cover most memory-failure.c functions.
function test_hwpoison()
{
	rlPhaseStartTest "hwpoison-inject"
		pushd mce-test
		rlRun "./runmcetest -t ./work/ -s ./summary -o ./results -b ./bin -l ../taskfiles/hwpoison-func -r 1" 0
		popd
	rlPhaseEnd
}

rlJournalStart
	if ! check_mce_support; then
		rstrnt-report-result "CONFIG_MEMORY_FAILURE disabled" SKIP
		exit 0
	elif ! check_hwpoison_support; then
		rstrnt-report-result "CONFIG_HWPOISON_INJECT disabled" SKIP
		exit 0
	elif ! uname -m | grep -E "x86_64"; then
		rstrnt-report-result "test only supports x86_64" SKIP
		exit 0
	fi

	rlPhaseStartSetup
		test_setup
	rlPhaseEnd

	test_hwpoison

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

