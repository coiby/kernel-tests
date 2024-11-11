#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of misc/reboot-test
#   Description: Simple reboot test
#   Author: Bruno Goncalves <bgoncalv@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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

TEST="misc/reboot-test"

if [[ ! -e kernel_before_reboot.txt ]]; then
    echo "Saving kernel info before reboot"
    uname -r > kernel_before_reboot.txt
    if type -p journalctl > /dev/null; then
        date +"%F %T" > start_time.txt
        # save the start time of the test so later on can search journalctl for call traces
        # if /var/log/journal doesn't exist create it to make logs persistent
        if [ ! -d /var/log/journal ]; then
            echo "INFO: enabling persistent storage for journalctl"
            mkdir -p /var/log/journal
            journalctl --flush
        fi
        journalctl -n0 -q --show-cursor | cut -d ' ' -f3- > cursor.txt
    fi
    echo "Reboot now!"
    rstrnt-reboot
    # Make sure the script doesn't continue if rstrnt-reboot get's killed
    # https://github.com/beaker-project/restraint/issues/219
    exit 0
else
    check_version_status="FAIL"
    call_trace_status="FAIL"
    echo "Saving kernel info after reboot"
    uname -r > kernel_after_reboot.txt
    if diff kernel_before_reboot.txt kernel_after_reboot.txt; then
        check_version_status="PASS"
        echo "Rebooted using correct kernel"
        cat kernel_after_reboot.txt
    else
        echo "FAIL: Rebooted using different kernel"
        echo -n "Before reboot: "
        cat kernel_before_reboot.txt
        echo -n "After reboot: "
        cat kernel_after_reboot.txt
    fi
    rm -f kernel_before_reboot.txt
    rstrnt-report-result ${TEST}/kernel-version-check ${check_version_status} 0

    if type -p journalctl > /dev/null; then
        JOURNALCTLLOG=journalctl.log
        start_time=$(cat start_time.txt)
        cursor=$(cat cursor.txt)
        # check if there was any call trace during boot or during reboot
        echo "INFO: journalctl log should have entries since ${start_time}..."
        journalctl --after-cursor "${cursor}" > ${JOURNALCTLLOG}
        if grep -qi 'Call Trace:' ${JOURNALCTLLOG}; then
          echo "FAIL: Call trace found in journalctl, see journalctl.log"
        else
          call_trace_status="PASS"
        fi
        rstrnt-report-result -o "${JOURNALCTLLOG}" ${TEST}/journalctl-check ${call_trace_status} 0
    fi
fi
