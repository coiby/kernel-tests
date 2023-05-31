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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="kernel"

rlJournalStart
    rlPhaseStartSetup
        "dnf install -y perf python3 @development" 0
        rlShowRunningKernel
        rlRun "git clone https://github.com/sjp38/masim.git" 0
        rlRun "pip install -U damo" 0
        pushd masim
        rlRun "make" 0
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "./masim ./configs/zigzag.cfg &" 0
        rlRun "damo record -o damon.data $(pidof masim)" 0
        rlRun "damo report heats --heatmap stdout" 0
    rlPhaseEnd

    rlPhaseStartCleanup
        popd
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
