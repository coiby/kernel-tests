#!/bin/sh
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh

opt=${TESTARGS:-"0"}

BuildCrasher()
{
    opt=${TESTARGS}
    Log "Prepare trigger crash-crasher panic with opt: ${opt}"
    MakeModule 'crasher'
    if [[ "$(getenforce)" = "Enforcing" && $(uname -r) =~ .*\.el7\..* ]]; then
        Log "Fixing SELinux label on crasher.ko on RHEL7"
        LogRun "chcon -t modules_object_t crasher/crasher.ko"

    fi
    LogRun "insmod crasher/crasher.ko" || MajorError "Unable to load crasher.ko."
    LogRun "lsmod | grep crasher"


    # workaround for bug 810201
    Log "Enable panic_on_oops"
    echo 1 > /proc/sys/kernel/panic_on_oops

    # Workaround "No module <module-name> found for kernel <kernel version>, aborting."
    # https://access.redhat.com/solutions/180113
    if $IS_RHEL6 && grep -q -E ^MKDUMPRD_ARGS=.*allow-missing ${KDUMP_SYS_CONFIG}; then
        Log "Changing MKDUMPRD_ARGS in ${KDUMP_SYS_CONFIG} to allow crash.ko"
        sed -i 's/MKDUMPRD_ARGS="/MKDUMPRD_ARGS="--allow-missing /g' ${KDUMP_SYS_CONFIG}
        RhtsSubmit ${KDUMP_SYS_CONFIG}
    fi

    # Hard lockup panic
    if [[ "${opt}" = 3 ]]; then
        # Enable nmi_watchdog and hardlockup_panic
        # for testing the hard lockup
        Log "Enable nmi_watchdog and hardlockup_panic"
        echo 1 > /proc/sys/kernel/hardlockup_panic
        echo 1 > /proc/sys/kernel/nmi_watchdog

        # Workaround bug 703334
        [[ "${ARCH}" == i?86 ]] && service cpuspeed stop

        # Restart kdump service if ppc64/ppc64le
        [[ "${ARCH}" == ppc64* ]] && {
            touch ${KDUMP_CONFIG}
            kdumpctl restart > /dev/null 2>&1 || service kdump restart > /dev/null 2>&1
        }
    fi
}

TriggerCrasher()
{
    Log "Trigger crasher panic with opt: ${opt}"
    sync;sync;sync; sleep 10
    echo "${opt}" > /proc/crasher
}

#+---------------------------+

Multihost SystemCrashTest TriggerCrasher BuildCrasher