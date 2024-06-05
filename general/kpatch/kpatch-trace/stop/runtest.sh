#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch-trace/stop
#   Description: Disable kpatch-patch functions tracing and
#		and collect stats
#   Authors: Joe Lawrence <joe.lawrence@redhat.com>
#  	     Yulia Kopkova <ykopkova@redhat.com>
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

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/share/rhts-library/rhtslib.sh

KPATCH_PATCH="${KPATCH_PATCH:-}"
SYSFS=/sys/kernel
STATS_DIR=/mnt/testarea/kpatch-trace

if [ -n "$KPATCH_PATCH" ]; then
	KPATCH_FILE="$(rpm -ql $KPATCH_PATCH | grep -E 'kpatch-.*\.ko')"
fi

if [ -z "$KPATCH_FILE" ]; then
	KPATCH_FILE="$(ls /usr/lib/kpatch/$(uname -r)/kpatch-* | head -n 1)"
fi

KPATCH_MODULE="$(modinfo --field=name $KPATCH_FILE)"

patched_functions()
{
	local module="$1"
	local f

	# For each /sys/kernel/livepatch/<patch>/<object>/<function,sympos>
	for f in $SYSFS/livepatch/$module/*/*,[0-9]*; do

		file=$(basename "$f")
		function="${file%%,*}"

		echo "$function"
	done | sort -u
}

rlJournalStart
	rlPhaseStartTest
		rlLog "For each $SYSFS/livepatch/<patch>/<object>/<function,sympos>"
		echo "# Patched functions:" > $STATS_DIR/patched
		pf=$(patched_functions "$KPATCH_MODULE" | tee -a $STATS_DIR/patched)
		rlFileSubmit $STATS_DIR/patched
		rlLog "Stop ftrace and dump out unique filter function hits"
		rlRun "echo 0 > $SYSFS/debug/tracing/tracing_on"
		echo "# Traced functions:" > $STATS_DIR/traced
		tf=$(sort -u $STATS_DIR/stats | tee -a $STATS_DIR/traced)
		rlFileSubmit $STATS_DIR/traced
		echo "# Code that was modified but didn't run:" > $STATS_DIR/diff
		not_ex=$(comm -23 <(echo "$pf") <(echo "$tf") | tee -a $STATS_DIR/diff)
		rlFileSubmit $STATS_DIR/diff
		[ -n "$not_ex" ] && ( rlLogWarning "Code that was modified but didn't run:" ; rlLogWarning "$not_ex" ) \
			|| rlPass "All patched functions were triggered"
		echo "# Other code that ftrace saw, but is not listed in the sysfs directory:" > $STATS_DIR/other
		comm -13 <(echo "$pf") <(echo "$tf") | tee -a $STATS_DIR/other
		rlFileSubmit $STATS_DIR/other
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
