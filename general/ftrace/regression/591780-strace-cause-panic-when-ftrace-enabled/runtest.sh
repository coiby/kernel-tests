#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/ftrace/regression/591780-strace-cause-panic-when-ftrace-enabled
#   Description: Bug 591780 - The kernel crashes if strace is executed while ftrace is enabled
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: Qiao Zhao <qzhao@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../include/runtest.sh || exit 1

TARGET=testprog

rlJournalStart
    rlPhaseStartSetup
        rlRun "tar xzf ${TARGET}.tgz"
        rlRun "pushd ${TARGET}"
        rlRun "make"
        rlRun "popd"
        rlRun "chmod a+x ${TARGET}/run.sh"
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "trace-cmd start -e signal" 0 || rlDie
        rlRun "pushd ${TARGET}"
        rlRun "./run.sh" 0
        rlRun "popd"
        rlLog "Still alive"
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "trace-cmd stop"
        rlRun "trace-cmd reset"
    rlPhaseEnd
rlJournalEnd
