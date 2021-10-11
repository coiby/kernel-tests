#!/bin/bash

#--------------------------------------------------------------------------------
# Copyright (c) 2019 Red Hat, Inc. All rights reserved. This copyrighted material
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
#---------------------------------------------------------------------------------

# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
# Run jcstress test
  rlPhaseStartTest
    rlRun -l "wget https://arr-cki-prod-lookaside.s3.us-east-1.amazonaws.com/lookaside/static/jcstress-20210920.jar -O jcstress.jar"
    if [ $? -ne 0 ]; then
        cki_abort_task
    fi
    rlRun -l "java -jar jcstress.jar -m quick -t samples"
  rlPhaseEnd

rlJournalEnd
rlJournalPrintText
