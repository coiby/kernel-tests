#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch-trace/start
#   Description: Enable kpatch-patch functions tracing
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
	KPATCH_FILE="$(rpm -ql $KPATCH_PATCH | grep -E kpatch-.*\.ko)"
fi

if [ -z "$KPATCH_FILE" ]; then
	KPATCH_FILE="$(ls /var/lib/kpatch/$(uname -r)/* | grep kpatch- | head -n 1)"
fi

KPATCH_MODULE="$(modinfo --field=name $KPATCH_FILE)"

rlJournalStart
	rlPhaseStartSetup
		rlAssertRpm kpatch
		if [ ! -e "/sys/module/$KPATCH_MODULE" ]; then
		    rlRun "kpatch load $KPATCH_FILE" || rlDie "Cannot load $KPATCH_FILE"
		fi
		rlAssertEquals "Assert $KPATCH_MODULE is enabled" "$(cat $SYSFS/livepatch/$KPATCH_MODULE/enabled)" "1" \
			||  rlDie "Livepatch module $KPATCH_MODULE is not enabled."
		rlPhaseEnd

	rlPhaseStartTest
		rlShowRunningKernel
		rlLog "Clear old ftrace data"
		rlRun "echo 0 > $SYSFS/debug/tracing/tracing_on"
		rlRun "echo > $SYSFS/debug/tracing/set_ftrace_filter"
		rlRun "echo > $SYSFS/debug/tracing/trace"

		rlLog "Turn on ftrace and dump the buffer"
		rlRun "echo *:mod:$KPATCH_MODULE >> $SYSFS/debug/tracing/set_ftrace_filter"
		rlRun "echo function > $SYSFS/debug/tracing/current_tracer"
		rlRun "echo 1 > $SYSFS/debug/tracing/tracing_on"

		rlLog "Enable kpatch functions tracing on system startup"
		echo "#!/usr/bin/bash
echo *:mod:$KPATCH_MODULE >> $SYSFS/debug/tracing/set_ftrace_filter
echo function > $SYSFS/debug/tracing/current_tracer
echo 1 > $SYSFS/debug/tracing/tracing_on" > /usr/local/bin/enable-kpatch-trace.sh
		chmod +x /usr/local/bin/enable-kpatch-trace.sh
		mkdir -p /usr/local/lib/systemd/system/
		echo "[Unit]
After=kpatch.service
Description=Runs /usr/local/bin/enable-kpatch-trace.sh
[Service]
ExecStart=/usr/local/bin/enable-kpatch-trace.sh
[Install]
WantedBy=multi-user.target" > /usr/local/lib/systemd/system/kpatch-trace.service
		systemctl enable kpatch-trace

		rlLog "Add cron job to save stats every 1 min"
		mkdir -p $STATS_DIR
		> $STATS_DIR/stats
		echo "#!/usr/bin/bash
comm -23 <(sed -e 's/^.*[0-9]:[ ]//' -e 's/[ ].*$//' /sys/kernel/debug/tracing/trace | grep -v '#' | sort -u) <(sort -u $STATS_DIR/stats) >> $STATS_DIR/stats" > /usr/local/bin/kpatch-trace-stats.sh
		chmod +x /usr/local/bin/kpatch-trace-stats.sh
		echo "* * * * * root /usr/local/bin/kpatch-trace-stats.sh" > /etc/cron.d/kpatch-trace.job
            rlPhaseEnd
rlJournalPrintText
rlJournalEnd
