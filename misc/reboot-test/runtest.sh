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
    echo "Reboot now!"
    rstrnt-reboot
    # Make sure the script doesn't continue if rstrnt-reboot get's killed
    # https://github.com/beaker-project/restraint/issues/219
    exit 0
else
    echo "Saving kernel info after reboot"
    uname -r > kernel_after_reboot.txt
    if diff kernel_before_reboot.txt kernel_after_reboot.txt; then
        echo "Rebooted using correct kernel"
        cat kernel_after_reboot.txt
        rstrnt-report-result "${TEST}" "PASS"
        exit 0
    else
        echo "FAIL: Reooted using different kernel"
        echo -n "Before reboot: "
        cat kernel_before_reboot.txt
        echo -n "After reboot: "
        cat kernel_after_reboot.txt
        rstrnt-report-result "${TEST}" "FAIL"
        exit 1
    fi
fi
