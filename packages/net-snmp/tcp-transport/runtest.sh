#!/bin/bash

# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted material 
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Jan Safranek

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)


# include common routines
source $CDIR/../../cki_lib/libcki.sh || exit
source $CDIR/../testlib/net-snmp-lib.sh

rlJournalStart

rlPhaseStartSetup
    if [ `rlGetDistroRelease` -eq 4 ]; then
        # on rhel4, no tcp port can be bound by snmpd...
        setenforce 0
    fi
    nsPrepareService
rlPhaseEnd

rlPhaseStartTest
    rlRun "rlServiceStart snmpd"

    # port 1161 is open in selinux policy...
    rlRun -s "snmpwalk tcp:localhost:1161 sysLocation" 0 "Check the server is online"
    rlAssertGrep "sysLocation.*Unknown" $rlRun_LOG

    rm $rlRun_LOG
    
    rlRun "nsCheckAndStop snmpd"
rlPhaseEnd


rlPhaseStartCleanup
    if [ `rlGetDistroRelease` -eq 4 ]; then
        setenforce 1
    fi
    rlRun "nsCleanup"
rlPhaseEnd

rlJournalPrintText
