#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/damon
#   Description: DAMON: Data Access MONitor verification
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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

# Include Beaker environment
if [ -f /usr/bin/rhts-environment.sh ]; then
    . /usr/bin/rhts-environment.sh || exit 1
fi
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="kernel"

rlJournalStart
    rlPhaseStartSetup
        if [ -f /boot/config-$(uname -r) ]; then
            if ! grep -q "CONFIG_DAMON=y" /boot/config-$(uname -r); then
                rlLog "DAMON not supported, Skip"
                rstrnt-report-result "$RSTRNT_TASKNAME" SKIP
                exit 0
            fi
        else
            rlLog "can't confirm DAMON"
            rstrnt-report-result "$RSTRNT_TASKNAME" SKIP
            exit 0
        fi
        rlRun "dnf install -y perf python3 python3-pip @development" 0
        rlShowRunningKernel
        rlRun "git clone https://github.com/sjp38/masim.git" 0
        if [ $? != 0 ]; then
                rlLog "git clone fail"
                rstrnt-report-result "$RSTRNT_TASKNAME" FAIL 99
                exit 0
        fi
        rlRun "pip3 install -U damo" 0
        pushd masim || exit
        # checkout latest stable commit
        rlRun "git checkout -q bbeab0c3ca431c4691301197e7ea46312a5a630f" 0
        rlRun "make" 0
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "./masim ./configs/zigzag.cfg &" 0
        rlRun "damo record -o damon.data $(pidof masim)" 0
        rlRun "damo report heats --heatmap stdout" 0
    rlPhaseEnd

    rlPhaseStartCleanup
        popd || exit
        rlRun "rm -rf masim" 0
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
