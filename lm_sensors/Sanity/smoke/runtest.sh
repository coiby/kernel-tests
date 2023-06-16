#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/lm_sensors/Sanity/smoke
#   Description: lm_sensors smoke test
#   Author: Petr Splichal <psplicha@redhat.com>
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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



EnterGenerator="{ while true; do echo -e '\n'; sleep 1; done; }"
rlJournalStart
    # workaround due to https://bugzilla.redhat.com/show_bug.cgi?id=2119594
    # moved the skip inside the beakerlib framework so that tmt would not fail during skip.
    if [ "$(uname -i)" != "aarch64" ];then
        rlPhaseStartSetup Setup
            rlRun "TmpDir=\`mktemp -d\`" 0 "Creating tmp directory"
            rlRun "rlFileBackup /etc/sysconfig/lm_sensors"
            rlRun "pushd $TmpDir"

            rlLog "lm_sensors version: $(rpm -q lm_sensors)"
            rlLog "kernel version: $(uname -r)"
        rlPhaseEnd

        rlPhaseStartTest Testing
            # detect sensors
            rlRun "$EnterGenerator | sensors-detect 2>&1 | tee detection" \
                    0 "Detecting available sensors"
            rlAssertNotGrep "Sorry, no.*detected" "detection"

            # investigate detected sensors
            rlLog "lm_sensors service only needed for modules that don't autoload, warn if fail to start"
            rlLog "Starting lm_sensors"
            service lm_sensors start
            RETURNCODE="$?"
            if [[ $RETURNCODE -ne 0 ]]; then
                rlLogWarning "lm_sensors failed to start, is module autoloaded?"
            else
                rlPass "lm_sensors started normally"
            fi

            eval "$(grep 'HWMON_MODULES=\|BUS_MODULES=' /etc/sysconfig/lm_sensors)"
            rlRun "test -n '$HWMON_MODULES' -o -n '$BUS_MODULES'" 0,1 \
                    "$HWMON_MODULES or $BUS_MODULES is sometimes empty depending on BMC implementation"
            for module in $HWMON_MODULES $BUS_MODULES; do
                rlRun "lsmod | grep $module"
            done

            rlRun "sensors 2>&1 | tee display" 0 "Displaying sensors"
            if rlAssertNotGrep "No sensors" "display"; then
                sensors=$(perl -e "print join ' ', sort((join '', <stdin>)
                                =~ m/([:\s]+)$/gm)" < display)
                sensorscount=$(echo "$sensors" | wc -w)
            else
                sensors="none"
                sensorscount="0"
            fi
            rlLog "Sensors found: $sensorscount ($sensors)"

            # investigate detected drivers
            if rlRun "grep Driver detection | grep -v to-be-written > drivers" \
                    0 "Investigating detected drivers"; then
                drivers=$(perl -e "print join ' ', sort((join '', <stdin>)
                                =~ m/Driver \\\`(.*)'/g)" < drivers)
                driverscount=$(echo "$drivers" | wc -w)
            else
                drivers="none"
                driverscount="0"
            fi
            rlLog "Drivers found: $driverscount ($drivers)"
            rlRun "cat /etc/sysconfig/lm_sensors"
        rlPhaseEnd

        rlPhaseStartCleanup Cleanup
            rlRun "popd"
            rlRun "rlFileRestore"
            rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        rlPhaseEnd
    else
         rstrnt-report-result "/kernel/lm_sensors/Sanity/smoke" SKIP
    fi
rlJournalPrintText
rlJournalEnd
