#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/hw-enablement/removable-media/SD-card
#   Description: SD card read/write/compare test.
#   Author: Mike Gahagan <mgahagan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
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
. ../include/include.sh || exit 1
TEST=${TEST:-"SD-card"}
TESTNAME=$(basename "$TEST")
# Set unique log file.
OUTPUTDIR=/mnt/testarea/$TESTNAME
if ! [ -d "$OUTPUTDIR" ]; then
    echo "Creating $OUTPUTDIR"
    mkdir -p "$OUTPUTDIR"
fi

log_dir=$OUTPUTDIR/logs
DeBug=1 # set to 1 to turn on debugging

rlJournalStart
    rlPhaseStartSetup
        rlGetDistroRelease
        rlGetDistroVariant
        rlShowRunningKernel
        rlGetPrimaryArch
        rlGetSecondaryArch
        rlRun "mkdir -p $OUTPUTDIR/{logs,SD_mnt,scratch}" 0 "Making output directories"
        [ $? -eq 0 ] || rlDie "Cannot make output directories!... aborting.."
        rlRun "install_dt" 0 "Installing dt..."
    rlPhaseEnd

    rlPhaseStartTest
        if [[ $DeBug = 1 ]]; then
            # shellcheck disable=SC2034
            HEADER=$(echo "$HOSTNAME" | cut -d . -f 1)
            # Get debug info here
        fi
        rlRun "PYTHONPATH=$PYTHONPATH:../include/ ./test_sd.py $(build_params)" 0 "Running SD card test..."
    rlPhaseEnd

    rlPhaseStartCleanup
      for f in $log_dir/*; do
        if [ -f "$f" ] ; then
          rlFileSubmit "$f"
        fi
      done
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
