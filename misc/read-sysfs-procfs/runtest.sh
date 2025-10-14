#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

if [ "$1" != "start" ] && [ "$1" != "stop" ]; then
    echo "Usage: $0 {start|stop}"
    exit 1
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if [ "$1" == "start" ]; then
            rlRun "cp /usr/bin/find /var/qm/tmp/"
        fi
    rlPhaseEnd
    rlPhaseStartTest Start reading all sysfs and procfs entries continuously
        if  [ "$1" == "start" ]; then
            rlRun "tmux new-session -d -s sysfs 'podman exec qm bash -c \"while true; do /var/tmp/find /sys -type f -not -writable -exec cat {} \\; ; done\"'"
            rlRun "tmux new-session -d -s procfs 'podman exec qm bash -c \"while true; do /var/tmp/find /proc -type f -not -writable -exec cat {} \\; ; done\"'"
        elif [ "$1" == "stop" ]; then
            rlRun "tmux kill-session -t sysfs"
            rlRun "tmux kill-session -t procfs"
        fi
    rlPhaseEnd
    if [ "$1" == "stop" ]; then
        rlPhaseStartCleanup
            rlRun "rm -f /var/qm/tmp/find"
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
