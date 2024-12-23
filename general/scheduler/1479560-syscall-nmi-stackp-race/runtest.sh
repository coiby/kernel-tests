#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1479560
#   Description: This is a tests for sp race in syscall and nmi.
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1

if [ -z "$OUTPUTFILE" ]; then
	export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

function Cleanup()
{
	exit 1
}

rlJournalStart
	rlPhaseStartSetup
		rlRun "gcc syscall.c -o syscall" || rlDie "syscaller failed to compile!"
		uname -r | grep ppc64le && need_skip=1
	rlPhaseEnd
if ((need_skip)); then
	rlPhaseStartTest "skip as ppc64le bz1536287"
	rlPhaseEnd
else
	rlPhaseStartTest
		NR_CORES=$(grep -wc processor /proc/cpuinfo)
		SYS_TASKS=""
		for i in $(seq 0 $((NR_CORES -1 ))); do
			rlRun "taskset -c $i ./syscall &"
			SYS_TASKS+="$! "
		done
		nproc=$(nproc --all)
		if ((nproc > 16)); then
			loop=2
		elif ((nproc > 8)); then
			loop=4
		else
			loop=8
		fi
		for i in $(seq 1 $loop); do
			true
			rlRun "echo l > /proc/sysrq-trigger"
		done
	rlPhaseEnd
fi

	rlPhaseStartCleanup
		for pid in $SYS_TASKS; do
			rlRun "kill $pid" 0-255 "Killing syscallers..."
		done
		make clean
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

