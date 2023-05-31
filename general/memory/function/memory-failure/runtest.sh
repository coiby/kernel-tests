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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

. powerpc.sh

function check_hwpoison_support()
{
	grep -E 'CONFIG_HWPOISON_INJECT=[ym]' /boot/config-$(uname -r)
}

function check_mce_support()
{
	grep -E 'CONFIG_MEMORY_FAILURE=[y|m]' /boot/config-$(uname -r)
	#grep -E 'CONFIG_X86_MCE=[y|m]' /boot/config-$(uname -r) &&
	#grep -E 'CONFIG_X86_MCE_INJECT=[ym]' /boot/config-$(uname -r)
}

function test_setup()
{
	local ret=0
	test -d mce-test && rm -fr mce-test
	echo "Getting mce-test suit ..."
	git clone git://git.kernel.org/pub/scm/utils/cpu/mce/mce-test.git
	pushd mce-test &> /dev/null
	make && make install || ret=8
	popd

	[ ! $ret = 0 ] && return $ret

	echo "Getting mce-inject suit ..."
	git clone git://git.kernel.org/pub/scm/utils/cpu/mce/mce-inject.git
	pushd mce-inject &> /dev/null
	make && make install || ret=4
	popd

		[ ! $ret = 0 ] && return $ret

	echo "Installing mcelog ..."
	yum -y install mcelog || ret=2
	[ $ret = 0 ] || rlDie "Test setup failed: no match for package mcelog"

	uname -m | grep ppc64le && ppc64le_setup

	return $ret
}

# Cover most memory-failure.c functions.
function test_hwpoison()
{
	# run x86 mce_test in non-x86
	[ "$FORCE_MCE_TEST" = 1 ] || uname -m | grep x86 || return
	[[ "$phase" =~ Skip ]] && return
	rlPhaseStartTest "hwpoison-inject"
		pushd mce-test
		rlRun "./runmcetest -t ./work/ -s ./summary -o ./results -b ./bin -l ../taskfiles/hwpoison-func -r 1" 0
		popd
	rlPhaseEnd
}

rlJournalStart
	if check_mce_support && check_hwpoison_support; then
		phase="Test"
	else
		echo "memory-failure is not supported. skip test."
		phase="Skip-not-support"
	fi
	rlPhaseStartSetup
	[ "$phase" = Test ] && test_setup
	rlPhaseEnd

	rlPhaseStartTest $phase
		uname -m | grep ppc64le || test_hwpoison
		# If this still can happen? If so, i'll try to file a new defect/bug.
		# https://bugzilla.redhat.com/show_bug.cgi?id=1706088
		uname -m | grep ppc64le && ppc64le_run
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

