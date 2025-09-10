#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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

# Include beakerlib environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

LATENCY_THRES_US=${LATENCY_THRES_US:-51000}

function timerlat_setup() {
    # Temporarily stop the timerlat tracing service if it is active (VROOM-23444)
    if systemctl is-active --quiet timerlat_trace; then
        rlLog "'timerlat_trace' service is currently active. Temporarily stopping it to avoid conflicts."
        rlRun "systemctl stop timerlat_trace"
        rlRun "touch /var/tmp/timerlat_trace_stopped"
    else
        rlLog "'timerlat_trace' service is not active. Proceeding with the test."
        rlRun "rm -f /var/tmp/timerlat_trace_stopped"
    fi
}

function timerlat_start() {
    rlRun "tmux new-session -d -s timerlat 'rtla timerlat hist -d \"24h\" -u | tee /var/tmp/timerlat_hist.txt'"
}

function timerlat_report_results() {
    rlRun "killall -s SIGINT rtla"
    while pgrep -x rtla > /dev/null; do
        rlLog "rtla processes still running: $(pgrep -x rtla | wc -l)"
        sleep 1
    done
    rlFileSubmit /var/tmp/timerlat_hist.txt
    # Extract the maximum latency value from the timerlat_hist.txt file and log the latency results
    max_latency=$(grep "max:" /var/tmp/timerlat_hist.txt | awk -F":" '{print $2}' | tr ' ' '\n' | grep -E "[0-9]+" | awk '$0>x {x=$0}; END{print x}')
    if [[ -z $max_latency ]]; then
        rlFail "Unable to get maximum latency. Refer to timerlat_hist.txt for detailed results."
    elif [[ $max_latency -gt $LATENCY_THRES_US ]]; then
        rlFail "Maximum latency is $max_latency us, which exceeds threshold $LATENCY_THRES_US. Refer to timerlat_hist.txt for detailed results."
    else
        rlPass "System latency within acceptable range: $max_latency us (threshold is $LATENCY_THRES_US)."
    fi
    # Restore the timerlat tracing service if it was stopped earlier
    if [[ -f /var/tmp/timerlat_trace_stopped ]]; then
        rlRun "systemctl start timerlat_trace"
        rlRun "rm -f /var/tmp/timerlat_trace_stopped"
    fi
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    if [[ "$1" == "start" ]]; then
        rlPhaseStartTest "Start latency measurement"
            rlRun timerlat_setup
            rlRun timerlat_start
        rlPhaseEnd
    fi
    if [[ "$1" == "stop" ]]; then
        rlPhaseStartTest "Report latency results"
            rlRun timerlat_report_results
        rlPhaseEnd
    fi
rlJournalEnd
