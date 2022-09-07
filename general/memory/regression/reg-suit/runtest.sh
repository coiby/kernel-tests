#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of memory regression test-suit
#   Description: TestCaseComment
#   Author: Chao Ye <cye@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
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
. ./lib/lib.sh
. ../../../include/libmem.sh || exit 1

trap 'rlFileRestore; exit' SIGHUP SIGINT SIGQUIT SIGTERM

export CPUCOUNT=$(grep -c -w  processor /proc/cpuinfo)
export DIR_CASE=$PWD/testcase
export DIR_SOURCE=$DIR_CASE/source
export DIR_MODULE=$DIR_CASE/module
export DIR_DONE=$PWD/testDone
export DIR_BIN=$DIR_ENTRY/debug/bin


BZLIST=${BZLIST:-}
SKIPLIST=${SKIPLIST:-}

declare -A KNOWN_ISSUE_LIST
declare -A KNOWN_FILED_BUGS
# Test bz1425895.sh reported bz1835556, Put the mapping into either of the arrays.
KNOWN_ISSUE_LIST["rhel8"]="bz1425895:bz1835556"
KNOWN_FILED_BUGS["bz1425895"]=" bz1835556"

function run_regression()
{
	local subcase
	local subfunc
	local findargs
	local pname
	local ptype

	findargs=$(echo $BZLIST | awk -v RS=' ' -v ORS=' ' '{print "-o -name bz*"$1"*.sh"}')
	for subcase in $(find $DIR_CASE -maxdepth 1 -name notexist $findargs); do
		ERR_STR=""
		. $subcase
		# Since 'basename -s' is not supported on rhel6, remove suffix '.sh' with bash parameter expansion.
		#subfunc=$(basename -s .sh $subcase)
		subfunc=$(basename ${subcase%.sh})
		funcname=$(echo $subfunc | cut -d '-' -f 1)
		pname=$subfunc
		ptype=FAIL
		echo ${funcname#bz} > $REBOOT_DOGFILE; sync; sleep 1
		echo "reg-suit ${subfunc} start" > /dev/kmsg;
		# If bzdeadline.sh reported bug bz1868611, the result will be like:
		# rlReport bzdeadline_bz1868611 WARN
		if echo ${KNOWN_ISSUE_LIST[$RELEASE]} | grep -q $subfunc; then
			ptype=WARN
			pname=${subfunc}_$(echo ${KNOWN_ISSUE_LIST[$RELEASE]} | awk -F: -v RS=' ' '/'$subfunc'/ {if (NF>1) {gsub(",","-unfix",$2);printf("unfix%s",$2)} else {printf("%s", $1)} exit 0}')
		elif echo ${!KNOWN_FILED_BUGS[*]} | grep -q $subfunc; then
			ptype=WARN
			pname=${subfunc}${KNOWN_FILED_BUGS[$subfunc]// /-unfix}
		fi

		rlPhaseStart $ptype $pname
		rlWatchdog "eval $funcname" 3600 "9"
		unset -f $funcname
		rlPhaseEnd
		[ ! -f $DIR_DEBUG/DEBUG ] && mv $subcase $DIR_DONE/
	done
}

function init_skip()
{
	local subcase
	lastpanic=$(cat $REBOOT_DOGFILE)
	for subcase in ${SKIPLIST} ${lastpanic}; do
		if [ ! -f "${DIR_CASE}/bz${subcase}*.sh" ]; then
			continue;
		fi
		rlPhaseStartTest "bz${subcase}_skipped"
		mark_skip "bz${subcase}" "skipped as global SKIPLIST env."
		rlPhaseEnd
		report_lastpanic
		mv "${DIR_CASE}/bz${subcase}*.sh" $DIR_DONE/
		. $DIR_DONE/bz${subcase}.sh
		if [[ $(type -t casecleanup) == function && -n $lastpanic ]]; then
			rlLog "cleanup..."
			casecleanup
			unset -f casecleanup
		fi
	done
}

function report_lastpanic()
{
	if [ -z "$lastpanic" ]; then
		return
	fi
	rlPhaseStartTest "bz${lastpanic}_panic"
	rlFail "bz${subcase} paniced! Please check console log for detail or check kdump vmcore!"
	rlPhaseEnd
}

rlJournalStart
rlPhaseStartSetup
	[ ! -d $DIR_DONE ] && rlRun "mkdir -p $DIR_DONE"
	[ ! -d $DIR_BIN ] && rlRun "mkdir -p $DIR_BIN"
	[ -f $REBOOT_DOGFILE ] && rlFail "Unexpected restart detected, please check." || rlRun "touch $REBOOT_DOGFILE"
	init_skip
	rlRun "TmpDir=\$(mktemp -d -p $DIR_ENTRY)" 0 "Creating tmp directory"
	rlRun "pushd $TmpDir"
rlPhaseEnd

run_regression

rlPhaseStartCleanup
	rlRun "popd"
	rlLogInfo "$(get_skip_summary)"
	[ ! -f $DIR_DEBUG/DEBUG ] && rlRun "rm -r $TmpDir" 0-254 "Removing tmp directory"
	rm -f $REBOOT_DOGFILE
	sed -i '/reboot_dogfile/d' /usr/bin/rhts-reboot
	make reset
rlPhaseEnd
rlJournalEnd
rlJournalPrintText
