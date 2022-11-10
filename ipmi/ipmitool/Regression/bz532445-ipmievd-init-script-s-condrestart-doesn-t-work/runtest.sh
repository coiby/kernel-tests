#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/ipmitool/Regression/bz532445-ipmievd-init-script-s-condrestart-doesn-t-work
#   Description: Test for bz532445 (ipmievd init script's condrestart doesn't work)
#   Author: Martin Cermak <mcermak@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2009 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

PACKAGE="ipmitool"

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlServiceStop ipmievd
        rlServiceStop ipmi
        rlServiceStart ipmi
        rlServiceStart ipmievd
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "/etc/init.d/ipmievd condrestart 2>&1 | grep -q \"restart: command not found\"" 1 "We should not get the \"restart: command not found\" error message."
    rlPhaseEnd

    rlPhaseStartCleanup
        rlServiceStop ipmievd
        rlServiceStop ipmi
        rlServiceRestore ipmi
        rlServiceRestore ipmievd
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd

