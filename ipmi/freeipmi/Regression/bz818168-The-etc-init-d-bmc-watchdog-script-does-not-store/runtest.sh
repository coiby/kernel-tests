#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/freeipmi/Regression/bz818168-The-etc-init-d-bmc-watchdog-script-does-not-store
#   Description: Test for BZ#818168 (The /etc/init.d/bmc-watchdog script does not store)
#   Author: Branislav Blaskovic <bblaskov@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="freeipmi"
PIDFILE="/var/run/bmc-watchdog.pid"
BMW_BINARY="/usr/sbin/bmc-watchdog"
# Work around for some systems where BMC fails to start watchdog
sed -ie '$s/"/"\-W ignorestateflag /' /etc/sysconfig/bmc-watchdog

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
        rlServiceStart "bmc-watchdog"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "service bmc-watchdog status"
    rlAssertEquals "compare pidof bmc-watchdog with pidfile value" x"$(pidof ${BMW_BINARY})" x"$(cat $PIDFILE)"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlServiceRestore "bmc-watchdog"
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
